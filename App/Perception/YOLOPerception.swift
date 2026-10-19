import CoreML
import ESPCore
import Vision

/// People (YOLO11s-pose, plus YOLO11s as a backup for half-hidden people) and animals (YOLO11s) via CoreML
/// on the Neural Engine.
/// Not thread-safe: call from one queue. `init` fails when the pose model is missing, fails to load or has an
/// unexpected output; the object model is optional (no animals without it).
final class YOLOPerception {
    private let poseRequest: VNCoreMLRequest
    private let objectRequest: VNCoreMLRequest?
    /// Pose model input in pixels (w × h), 4:3; `ModelInput` letterboxes other aspects so `.scaleFill` doesn't distort.
    private let inputSize = ModelInput.poseSize

    var hasObjectModel: Bool { objectRequest != nil }

    init?() {
        let config = MLModelConfiguration()
        config.computeUnits = .all
        guard let poseURL = Bundle.main.url(forResource: "pose", withExtension: "mlmodelc", subdirectory: "Models"),
              let pose = try? MLModel(contentsOf: poseURL, configuration: config),
              Self.hasPoseOutput(pose),
              let poseVision = try? VNCoreMLModel(for: pose)
        else { return nil }
        poseRequest = VNCoreMLRequest(model: poseVision)
        poseRequest.imageCropAndScaleOption = .scaleFill

        if let objectURL = Bundle.main.url(forResource: "objects", withExtension: "mlmodelc", subdirectory: "Models"),
           let objects = try? MLModel(contentsOf: objectURL, configuration: config),
           let objectVision = try? VNCoreMLModel(for: objects) {
            let request = VNCoreMLRequest(model: objectVision)
            request.imageCropAndScaleOption = .scaleFill
            objectRequest = request
        } else {
            objectRequest = nil
        }
    }

    /// The pose model must expose a 3-D multi-array output with a 56-wide axis (box + score + 17 × 3).
    private static func hasPoseOutput(_ model: MLModel) -> Bool {
        model.modelDescription.outputDescriptionsByName.values.contains { output in
            guard let constraint = output.multiArrayConstraint else { return false }
            let shape = constraint.shape.map(\.intValue)
            if shape.isEmpty { return true }  // shape not declared: decodePose still checks at run time
            return shape.count == 3 && (shape[1] == 56 || shape[2] == 56)
        }
    }

    /// People with skeletons, in captured-image coordinates. Weak boxes (down to 0.15) are kept: the tracker
    /// only lets them extend existing tracks. Each box is trimmed to the keypoints that can be seen, so a person
    /// behind a desk doesn't get a box over the desk.
    func people(in input: ModelInput.Prepared, orientation: VisionOrientation) -> [RawDetection] {
        let handler = VNImageRequestHandler(cvPixelBuffer: input.buffer, orientation: orientation == .down ? .down : .up, options: [:])
        guard (try? handler.perform([poseRequest])) != nil,
              let array = (poseRequest.results?.first as? VNCoreMLFeatureValueObservation)?.featureValue.multiArrayValue
        else { return [] }
        let (values, shape) = Self.floats(array)
        return YOLO.decodePose(values, shape: shape, inputSize: inputSize, boxThreshold: 0.15, keypointThreshold: 0.35).map { c in
            RawDetection(box: input.letterbox.toImage(VisionMapping.topLeftRect(PersonBox.visible(c.box, joints: c.joints),
                                                                               orientation: orientation)),
                         kind: .person,
                         confidence: c.confidence,
                         joints: c.joints.mapValues { input.letterbox.toImage(VisionMapping.topLeftPoint($0, orientation: orientation)) })
        }
    }

    /// Animals (tracked like people) and people (the plain detector finds half-hidden people the pose model
    /// misses), in captured-image coordinates.
    func things(in input: ModelInput.Prepared, orientation: VisionOrientation) -> (animals: [RawDetection], people: [RawDetection]) {
        guard let objectRequest else { return ([], []) }
        let handler = VNImageRequestHandler(cvPixelBuffer: input.buffer, orientation: orientation == .down ? .down : .up, options: [:])
        guard (try? handler.perform([objectRequest])) != nil,
              let observations = objectRequest.results as? [VNRecognizedObjectObservation]
        else { return ([], []) }

        var animals: [RawDetection] = [], people: [RawDetection] = []
        for observation in observations {
            guard let top = observation.labels.first else { continue }
            let b = observation.boundingBox
            let box = input.letterbox.toImage(VisionMapping.rect(Rect(x: Float(b.minX), y: Float(b.minY), width: Float(b.width),
                                                                      height: Float(b.height)), orientation: orientation))
            switch COCOClass(label: top.identifier) {
            case let .animal(kind):
                animals.append(RawDetection(box: box, kind: .animal(kind), confidence: top.confidence))
            case .person:
                people.append(RawDetection(box: box, kind: .person, confidence: top.confidence))
            case .other:
                break
            }
        }
        return (animals, people)
    }

    /// Copies a 3-D multi-array (Float16/Float32/Double, any strides) into a C-ordered Float array.
    /// Uses `withUnsafeBytes`, which is safe for pixel-buffer-backed outputs (Neural Engine Float16).
    static func floats(_ array: MLMultiArray) -> (values: [Float], shape: [Int]) {
        let shape = array.shape.map(\.intValue)
        let strides = array.strides.map(\.intValue)
        guard shape.count == 3 else { return ([], shape) }
        var out = [Float](repeating: 0, count: shape[0] * shape[1] * shape[2])
        let dataType = array.dataType

        array.withUnsafeBytes { raw in
            func fill(_ read: (Int) -> Float) {
                var k = 0
                for a in 0..<shape[0] {
                    for b in 0..<shape[1] {
                        let base = a * strides[0] + b * strides[1]
                        for c in 0..<shape[2] {
                            out[k] = read(base + c * strides[2])
                            k += 1
                        }
                    }
                }
            }
            switch dataType {
            case .float16:
                let p = raw.bindMemory(to: Float16.self)
                fill { Float(p[$0]) }
            case .float32:
                let p = raw.bindMemory(to: Float.self)
                fill { p[$0] }
            case .double:
                let p = raw.bindMemory(to: Double.self)
                fill { Float(p[$0]) }
            default:
                out = []
            }
        }
        return (out, shape)
    }
}
