/// One person from the pose model, normalized to the model input (top-left origin).
public struct PoseCandidate: Sendable {
    public var box: Rect
    public var confidence: Float
    public var joints: [Joint: Vec2]

    public init(box: Rect, confidence: Float, joints: [Joint: Vec2]) {
        self.box = box
        self.confidence = confidence
        self.joints = joints
    }
}

/// Decoding for Ultralytics YOLO pose output: per anchor cx, cy, w, h (input pixels), score,
/// then 17 COCO keypoints as (x, y, visibility).
public enum YOLO {
    static let channels = 56

    /// COCO keypoint order.
    static let keypoints: [Joint] = [
        .nose, .leftEye, .rightEye, .leftEar, .rightEar,
        .leftShoulder, .rightShoulder, .leftElbow, .rightElbow, .leftWrist, .rightWrist,
        .leftHip, .rightHip, .leftKnee, .rightKnee, .leftAnkle, .rightAnkle,
    ]

    /// Accepts `[1, 56, N]` or `[1, N, 56]`; anything else decodes to nothing.
    public static func decodePose(_ values: [Float], shape: [Int], inputSize: Vec2, boxThreshold: Float = 0.35,
                                  iouThreshold: Float = 0.5, keypointThreshold: Float = 0.5) -> [PoseCandidate] {
        guard shape.count == 3, shape[0] == 1 else { return [] }
        let channelsFirst: Bool, n: Int
        if shape[1] == channels {
            channelsFirst = true
            n = shape[2]
        } else if shape[2] == channels {
            channelsFirst = false
            n = shape[1]
        } else {
            return []
        }
        guard n > 0, values.count >= channels * n else { return [] }
        func value(_ c: Int, _ i: Int) -> Float { channelsFirst ? values[c * n + i] : values[i * channels + c] }

        var anchors: [Int] = [], boxes: [Rect] = [], scores: [Float] = []
        for i in 0..<n {
            let score = value(4, i)
            guard score >= boxThreshold else { continue }
            let cx = value(0, i), cy = value(1, i), w = value(2, i), h = value(3, i)
            anchors.append(i)
            scores.append(score)
            boxes.append(Rect(x: (cx - w / 2) / inputSize.x, y: (cy - h / 2) / inputSize.y,
                              width: w / inputSize.x, height: h / inputSize.y))
        }

        return nms(boxes, scores: scores, iouThreshold: iouThreshold).map { k in
            let i = anchors[k]
            var joints: [Joint: Vec2] = [:]
            for (j, joint) in keypoints.enumerated() where value(7 + 3 * j, i) >= keypointThreshold {
                joints[joint] = Vec2(value(5 + 3 * j, i) / inputSize.x, value(6 + 3 * j, i) / inputSize.y)
            }
            if let l = joints[.leftShoulder], let r = joints[.rightShoulder] { joints[.neck] = (l + r) / 2 }
            if let l = joints[.leftHip], let r = joints[.rightHip] { joints[.root] = (l + r) / 2 }
            return PoseCandidate(box: boxes[k], confidence: scores[k], joints: joints)
        }
    }

    /// Greedy non-maximum suppression. Returns the kept indices, best score first.
    public static func nms(_ boxes: [Rect], scores: [Float], iouThreshold: Float) -> [Int] {
        var kept: [Int] = []
        for i in boxes.indices.sorted(by: { scores[$0] > scores[$1] })
        where kept.allSatisfy({ boxes[$0].iou(boxes[i]) < iouThreshold }) {
            kept.append(i)
        }
        return kept
    }
}
