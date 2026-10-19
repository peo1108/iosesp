import CoreVideo
import ESPCore
import ImageIO
import Vision

/// Fallback people detector (Vision) for when the YOLO models can't load. Not thread-safe: call from one queue.
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

    /// People in captured-image coordinates (top-left origin) whatever `orientation` Vision ran in.
    func detect(in pixelBuffer: CVPixelBuffer, orientation: VisionOrientation) -> [RawDetection] {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer,
                                            orientation: orientation == .down ? .down : .up, options: [:])
        guard (try? handler.perform([rectangles, pose])) != nil else { return [] }

        var people = (rectangles.results ?? []).map { observation in
            let r = observation.boundingBox
            let box = Rect(x: Float(r.minX), y: Float(r.minY), width: Float(r.width), height: Float(r.height))
            return RawDetection(box: VisionMapping.rect(box, orientation: orientation), kind: .person,
                                // Vision's scores run low; keep fallback people above the tracker's "start" bar.
                                confidence: max(observation.confidence, 0.5))
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

        return people
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
