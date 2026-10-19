import CoreML
import ESPCore
import Vision

/// People (YOLO11n-pose) and animals/objects (YOLO11n) via CoreML on the Neural Engine.
/// Not thread-safe: call from one queue. `init` fails when the compiled models are missing from the bundle.
final class YOLOPerception {
    private let poseRequest: VNCoreMLRequest
    private let objectRequest: VNCoreMLRequest
    /// Model input in pixels (w × h): the camera's 4:3, so `.scaleFill` doesn't distort.
    private let inputSize = Vec2(640, 480)

    init?() {
        guard let poseURL = Bundle.main.url(forResource: "yolo11n-pose", withExtension: "mlmodelc", subdirectory: "Models"),
              let objectURL = Bundle.main.url(forResource: "yolo11n", withExtension: "mlmodelc", subdirectory: "Models")
        else { return nil }
        let config = MLModelConfiguration()
        config.computeUnits = .all
        do {
            poseRequest = VNCoreMLRequest(model: try VNCoreMLModel(for: MLModel(contentsOf: poseURL, configuration: config)))
            objectRequest = VNCoreMLRequest(model: try VNCoreMLModel(for: MLModel(contentsOf: objectURL, configuration: config)))
        } catch {
            return nil
        }
        poseRequest.imageCropAndScaleOption = .scaleFill
        objectRequest.imageCropAndScaleOption = .scaleFill
    }

    /// People with skeletons, in captured-image coordinates.
    func people(in buffer: CVPixelBuffer, orientation: VisionOrientation) -> [RawDetection] {
        let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: orientation == .down ? .down : .up, options: [:])
        guard (try? handler.perform([poseRequest])) != nil,
              let array = (poseRequest.results?.first as? VNCoreMLFeatureValueObservation)?.featureValue.multiArrayValue
        else { return [] }
        let (values, shape) = Self.floats(array)
        return YOLO.decodePose(values, shape: shape, inputSize: inputSize).map { c in
            RawDetection(box: VisionMapping.topLeftRect(c.box, orientation: orientation), kind: .person,
                         confidence: c.confidence,
                         joints: c.joints.mapValues { VisionMapping.topLeftPoint($0, orientation: orientation) })
        }
    }

    /// Animals (tracked like people) and objects (used for activities), in captured-image coordinates.
    func things(in buffer: CVPixelBuffer, orientation: VisionOrientation) -> (animals: [RawDetection], objects: [DetectedObject]) {
        let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: orientation == .down ? .down : .up, options: [:])
        guard (try? handler.perform([objectRequest])) != nil,
              let observations = objectRequest.results as? [VNRecognizedObjectObservation]
        else { return ([], []) }

        var animals: [RawDetection] = [], objects: [DetectedObject] = []
        for observation in observations {
            guard let top = observation.labels.first else { continue }
            let b = observation.boundingBox
            let box = VisionMapping.rect(Rect(x: Float(b.minX), y: Float(b.minY), width: Float(b.width), height: Float(b.height)),
                                         orientation: orientation)
            switch COCOClass(label: top.identifier) {
            case let .animal(kind) where top.confidence >= 0.35:
                animals.append(RawDetection(box: box, kind: .animal(kind), confidence: top.confidence))
            case let .object(kind) where top.confidence >= 0.3:
                objects.append(DetectedObject(kind: kind, box: box, confidence: top.confidence))
            default:
                break
            }
        }
        return (animals, objects)
    }

    /// Copies a 3-D multi-array (Float16/Float32/Double, any strides) into a C-ordered Float array.
    static func floats(_ array: MLMultiArray) -> (values: [Float], shape: [Int]) {
        let shape = array.shape.map(\.intValue)
        let strides = array.strides.map(\.intValue)
        guard shape.count == 3 else { return ([], shape) }
        var out = [Float](repeating: 0, count: shape[0] * shape[1] * shape[2])

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

        let pointer = array.dataPointer
        switch array.dataType {
        case .float16:
            let p = pointer.assumingMemoryBound(to: Float16.self)
            fill { Float(p[$0]) }
        case .float32:
            let p = pointer.assumingMemoryBound(to: Float.self)
            fill { p[$0] }
        case .double:
            let p = pointer.assumingMemoryBound(to: Double.self)
            fill { Float(p[$0]) }
        default:
            return ([], shape)
        }
        return (out, shape)
    }
}
