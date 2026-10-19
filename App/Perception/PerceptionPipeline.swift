import CoreVideo
import ESPCore
import Vision

/// Runs Vision on one camera image and returns the people in it. Not thread-safe: call from one queue.
final class PerceptionPipeline {
    private let rectangles: VNDetectHumanRectanglesRequest = {
        let request = VNDetectHumanRectanglesRequest()
        request.upperBodyOnly = false
        return request
    }()
    private let pose = VNDetectHumanBodyPoseRequest()

    private static let jointNames: [(Joint, VNHumanBodyPoseObservation.JointName)] = [
        (.nose, .nose), (.leftEye, .leftEye), (.rightEye, .rightEye), (.leftEar, .leftEar), (.rightEar, .rightEar),
        (.neck, .neck), (.leftShoulder, .leftShoulder), (.rightShoulder, .rightShoulder),
        (.leftElbow, .leftElbow), (.rightElbow, .rightElbow), (.leftWrist, .leftWrist), (.rightWrist, .rightWrist),
        (.root, .root), (.leftHip, .leftHip), (.rightHip, .rightHip),
        (.leftKnee, .leftKnee), (.rightKnee, .rightKnee), (.leftAnkle, .leftAnkle), (.rightAnkle, .rightAnkle),
    ]

    func detect(in pixelBuffer: CVPixelBuffer, wantMask: Bool) -> (people: [RawDetection], mask: CVPixelBuffer?) {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        do {
            try handler.perform([rectangles, pose])
        } catch {
            return ([], nil)
        }

        var people = (rectangles.results ?? []).map { observation in
            RawDetection(box: Self.topLeft(observation.boundingBox), joints: [:])
        }

        // Give each skeleton to the box that contains most of its joints.
        var bestShare = [Float](repeating: 0, count: people.count)
        for observation in pose.results ?? [] {
            let joints = Self.joints(of: observation)
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
        return (people, nil)
    }

    private static func joints(of observation: VNHumanBodyPoseObservation) -> [Joint: Vec2] {
        guard let points = try? observation.recognizedPoints(.all) else { return [:] }
        var joints: [Joint: Vec2] = [:]
        for (joint, name) in jointNames {
            if let p = points[name], p.confidence >= 0.3 {
                joints[joint] = Vec2(Float(p.location.x), Float(1 - p.location.y))
            }
        }
        return joints
    }

    /// Vision rects are bottom-left based.
    private static func topLeft(_ r: CGRect) -> Rect {
        Rect(x: Float(r.minX), y: Float(1 - r.minY - r.height), width: Float(r.width), height: Float(r.height))
    }
}
