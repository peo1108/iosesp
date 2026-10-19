import CoreVideo
import ESPCore
import ImageIO
import QuartzCore
import Vision

/// Runs Vision on one camera image and returns the people in it. Not thread-safe: call from one queue.
final class PerceptionPipeline {
    private let rectangles: VNDetectHumanRectanglesRequest = {
        let request = VNDetectHumanRectanglesRequest()
        request.upperBodyOnly = false
        return request
    }()
    private let pose = VNDetectHumanBodyPoseRequest()
    private let segmentation: VNGeneratePersonSegmentationRequest = {
        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = .balanced
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8
        return request
    }()
    private var lastMask: CFTimeInterval = 0

    private static let jointNames: [(Joint, VNHumanBodyPoseObservation.JointName)] = [
        (.nose, .nose), (.leftEye, .leftEye), (.rightEye, .rightEye), (.leftEar, .leftEar), (.rightEar, .rightEar),
        (.neck, .neck), (.leftShoulder, .leftShoulder), (.rightShoulder, .rightShoulder),
        (.leftElbow, .leftElbow), (.rightElbow, .rightElbow), (.leftWrist, .leftWrist), (.rightWrist, .rightWrist),
        (.root, .root), (.leftHip, .leftHip), (.rightHip, .rightHip),
        (.leftKnee, .leftKnee), (.rightKnee, .rightKnee), (.leftAnkle, .leftAnkle), (.rightAnkle, .rightAnkle),
    ]

    /// People in captured-image coordinates (top-left origin) whatever `orientation` Vision ran in.
    /// `mask` is a person-segmentation buffer in Vision's orientation, produced at most every 0.1 s and only
    /// when `wantMask` is set; nil otherwise. With `wantPeople` false (YOLO handles people) only the mask runs.
    func detect(in pixelBuffer: CVPixelBuffer, orientation: VisionOrientation, wantPeople: Bool = true,
                wantMask: Bool) -> (people: [RawDetection], mask: CVPixelBuffer?) {
        let now = CACurrentMediaTime()
        let maskDue = wantMask && now - lastMask >= 0.1
        guard wantPeople || maskDue else { return ([], nil) }
        var requests: [VNRequest] = wantPeople ? [rectangles, pose] : []
        if maskDue {
            requests.append(segmentation)
            lastMask = now
        }

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer,
                                            orientation: orientation == .down ? .down : .up, options: [:])
        do {
            try handler.perform(requests)
        } catch {
            return ([], nil)
        }

        let mask = maskDue ? segmentation.results?.first?.pixelBuffer : nil
        guard wantPeople else { return ([], mask) }

        var people = (rectangles.results ?? []).map { observation in
            let r = observation.boundingBox
            let box = Rect(x: Float(r.minX), y: Float(r.minY), width: Float(r.width), height: Float(r.height))
            return RawDetection(box: VisionMapping.rect(box, orientation: orientation), kind: .person,
                                confidence: observation.confidence)
        }

        // Give each skeleton to the box that contains most of its joints.
        var bestShare = [Float](repeating: 0, count: people.count)
        for observation in pose.results ?? [] {
            let joints = Self.joints(of: observation, orientation: orientation)
            guard joints.count >= 4 else { continue }
            var best: (index: Int, share: Float)?
            for (i, person) in people.enumerated() {
                let inside = joints.values.filter { person.box.contains($0) }.count
                let share = Float(inside) / Float(joints.count)
                if share >= 0.6, share > (best?.share ?? 0) { best = (i, share) }
            }
            if let best, best.share > bestShare[best.index] {
                people[best.index].joints = joints
                bestShare[best.index] = best.share
            }
        }

        return (people, mask)
    }

    private static func joints(of observation: VNHumanBodyPoseObservation, orientation: VisionOrientation) -> [Joint: Vec2] {
        guard let points = try? observation.recognizedPoints(.all) else { return [:] }
        var joints: [Joint: Vec2] = [:]
        for (joint, name) in jointNames {
            if let p = points[name], p.confidence >= 0.3 {
                joints[joint] = VisionMapping.point(Vec2(Float(p.location.x), Float(p.location.y)), orientation: orientation)
            }
        }
        return joints
    }
}
