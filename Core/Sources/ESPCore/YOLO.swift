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

/// Merging people from the plain detector (better with half-hidden people) into the pose model's.
public enum PersonFusion {
    /// Indices of `backups` not already covered by a box in `primary`: covered means over half of the smaller
    /// box overlaps (the pose boxes are trimmed to the visible body, so plain IoU would undercount).
    public static func uncovered(_ backups: [Rect], by primary: [Rect], overlap: Float = 0.5) -> [Int] {
        backups.indices.filter { i in
            let b = backups[i]
            return !primary.contains { p in
                let w = min(p.x + p.width, b.x + b.width) - max(p.x, b.x)
                let h = min(p.maxY, b.maxY) - max(p.y, b.y)
                guard w > 0, h > 0 else { return false }
                return w * h / max(min(p.area, b.area), 1e-6) > overlap
            }
        }
    }
}

/// Trims a person box to what can actually be seen. The detector draws the whole body it expects, so someone
/// half behind a desk or a monitor gets a box over the furniture too; the confident keypoints say where the body
/// really is. The result only ever shrinks the detector's box.
public enum PersonBox {
    /// `joints` in the same normalized coordinates as `box`; `aspect` is image width / height.
    public static func visible(_ box: Rect, joints: [Joint: Vec2], aspect: Float = 4.0 / 3.0) -> Rect {
        let points = joints.filter { $0.key != .neck && $0.key != .root }
        let shoulders = [joints[.leftShoulder], joints[.rightShoulder]].compactMap { $0 }
        guard points.count >= 5, !shoulders.isEmpty, let bounds = Rect.bounding(Array(points.values)) else { return box }

        // Body scale in image heights: torso length, else shoulder width, else the keypoints' spread.
        func length(_ a: Vec2, _ b: Vec2) -> Float { ((a - b) * Vec2(aspect, 1)).squareLength.squareRoot() }
        let hips = [joints[.leftHip], joints[.rightHip]].compactMap { $0 }
        let midShoulder = shoulders.reduce(Vec2.zero, +) / Float(shoulders.count)
        let unit: Float
        if !hips.isEmpty {
            unit = length(midShoulder, hips.reduce(Vec2.zero, +) / Float(hips.count))
        } else if shoulders.count == 2 {
            unit = length(shoulders[0], shoulders[1]) * 1.6
        } else {
            unit = bounds.height
        }
        guard unit > 0.01 else { return box }

        let head = [Joint.nose, .leftEye, .rightEye, .leftEar, .rightEar].compactMap { joints[$0]?.y }
        let top = head.min().map { $0 - 0.35 * unit } ?? bounds.minY - 0.6 * unit
        let feetSeen = joints[.leftAnkle] != nil || joints[.rightAnkle] != nil
        let bottom = bounds.maxY + (feetSeen ? 0.15 : 0.3) * unit
        let side = 0.35 * unit / aspect

        let x0 = max(box.x, bounds.x - side), x1 = min(box.x + box.width, bounds.x + bounds.width + side)
        let y0 = max(box.y, top), y1 = min(box.maxY, bottom)
        guard x1 - x0 > 0.2 * box.width, y1 - y0 > 0.2 * box.height else { return box }
        return Rect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }
}
