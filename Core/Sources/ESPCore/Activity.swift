import Foundation

// MARK: Vocabulary

public enum Motion: String, Sendable, CaseIterable {
    case still, walking, running
    /// On a bike or motorbike: faster than people run, or seated and moving.
    case riding

    public var emoji: String { ["🧍", "🚶", "🏃", "🛵"][Self.allCases.firstIndex(of: self)!] }
    public var text: String { ["Đứng yên", "Đi bộ", "Chạy", "Đi xe"][Self.allCases.firstIndex(of: self)!] }
}

public enum Posture: String, Sendable, CaseIterable {
    case standing, sitting, squatting, lying, bending

    public var emoji: String { ["🧍", "🪑", "🧎", "🛌", "🙇"][Self.allCases.firstIndex(of: self)!] }
    public var text: String { ["Đứng", "Ngồi", "Ngồi xổm", "Nằm", "Cúi người"][Self.allCases.firstIndex(of: self)!] }
}

public enum GestureKind: String, Sendable, CaseIterable {
    case none, raiseOne, raiseBoth, waving, armsCrossed, handsOnHips

    public var emoji: String { ["", "🙋", "🙌", "👋", "🙅", "💁"][Self.allCases.firstIndex(of: self)!] }
    public var text: String { ["", "Giơ tay", "Giơ 2 tay", "Vẫy tay", "Khoanh tay", "Chống nạnh"][Self.allCases.firstIndex(of: self)!] }
}

public enum Facing: String, Sendable, CaseIterable {
    case toward, away, side

    public var emoji: String { ["👁", "↩️", "↗️"][Self.allCases.firstIndex(of: self)!] }
    public var text: String { ["Đang nhìn bạn", "Quay lưng", "Nghiêng"][Self.allCases.firstIndex(of: self)!] }
}

public enum ObjectAction: String, Sendable, CaseIterable {
    case none, calling, usingPhone, drinking, usingLaptop, reading, cycling, motorbiking
    case lyingBed, sittingSofa, sittingChair, umbrella, playingBall

    public var emoji: String {
        ["", "📞", "📱", "☕", "💻", "📖", "🚲", "🏍", "🛏", "🛋", "🪑", "☂️", "⚽"][Self.allCases.firstIndex(of: self)!]
    }

    public var text: String {
        ["", "Gọi điện", "Dùng điện thoại", "Uống", "Dùng laptop", "Đọc sách", "Đi xe đạp", "Đi xe máy",
         "Nằm giường", "Ngồi sofa", "Ngồi ghế", "Cầm ô", "Chơi bóng"][Self.allCases.firstIndex(of: self)!]
    }
}

public enum Carry: String, Sendable, CaseIterable {
    case backpack, handbag

    public var emoji: String { self == .backpack ? "🎒" : "👜" }
    public var text: String { self == .backpack ? "Balo" : "Túi" }
}

/// Everything recognised about one person in one moment.
public struct ActivityFrame: Equatable, Sendable {
    public var posture: Posture
    public var motion: Motion
    public var gesture: GestureKind
    public var facing: Facing
    public var objectAction: ObjectAction
    public var carrying: [Carry]

    public init(posture: Posture, motion: Motion, gesture: GestureKind, facing: Facing,
                objectAction: ObjectAction, carrying: [Carry]) {
        self.posture = posture
        self.motion = motion
        self.gesture = gesture
        self.facing = facing
        self.objectAction = objectAction
        self.carrying = carrying
    }

    /// The headline: object action, else riding, else gesture, else a non-standing posture, else motion.
    public var main: (emoji: String, text: String) {
        if objectAction != .none { return (objectAction.emoji, objectAction.text) }
        if motion == .riding { return (motion.emoji, motion.text) }
        if gesture != .none { return (gesture.emoji, gesture.text) }
        if posture != .standing { return (posture.emoji, posture.text) }
        return (motion.emoji, motion.text)
    }
}

// MARK: Rules

/// Rule-based activity recognition from one upright skeleton (image y grows downward), the person's real
/// horizontal speed and the objects around. Distances are measured in torso lengths L (mid-shoulders to
/// mid-hips). Waving needs history and is decided by `ActivityTracker`.
public enum ActivityRules {
    /// Horizontal speed (m/s, ~23 km/h) above which someone on the street is on a vehicle, not running.
    public static let ridingSpeed: Float = 6.5
    /// Seated and moving at least this fast (m/s): riding a bike even when the bike isn't detected.
    static let seatedRidingSpeed: Float = 3.5

    public static func motion(speed: Float, posture: Posture) -> Motion {
        if speed >= ridingSpeed || (speed >= seatedRidingSpeed && posture == .sitting) { return .riding }
        return speed > 1.8 ? .running : speed >= 0.25 ? .walking : .still
    }

    public static func evaluate(joints j: [Joint: Vec2], box: Rect, speed: Float, objects: [DetectedObject]) -> ActivityFrame {
        let midShoulder = mid(j[.leftShoulder], j[.rightShoulder])
        let midHip = mid(j[.leftHip], j[.rightHip])
        let torso: Float? = midShoulder.flatMap { s in midHip.map { h in distance(s, h) } }
        let L = max(torso ?? box.height * 0.3, 0.01)

        var posture = postureOf(j, midShoulder: midShoulder, midHip: midHip, L: L)
        let motion = Self.motion(speed: speed, posture: posture)
        let gesture = gestureOf(j, L: L)
        let facing = facingOf(j, L: L)

        func near(_ kinds: Set<ObjectKind>, _ points: [Joint], within k: Float) -> Bool {
            objects.contains { o in
                kinds.contains(o.kind) && points.contains { p in j[p].map { distanceToBox($0, o.box) < k * L } ?? false }
            }
        }
        func holds(_ kinds: Set<ObjectKind>, point: Vec2?, grow: Float = 0) -> Bool {
            guard let point else { return false }
            return objects.contains { kinds.contains($0.kind) && distanceToBox(point, $0.box) <= grow * L }
        }

        // A seat under the hips turns a squat into sitting.
        let onSeat = holds([.chair, .couch, .bench], point: midHip, grow: 0.2)
        if posture == .squatting && onSeat { posture = .sitting }

        let lowerHalf = Rect(x: box.x, y: box.y + box.height / 2, width: box.width, height: box.height / 2)
        let laptopInReach = objects.contains { o in
            o.kind == .laptop && (o.box.iou(lowerHalf) > 0 || overlaps(o.box, lowerHalf))
                && (posture == .sitting || [Joint.leftWrist, .rightWrist].contains { w in
                    j[w].map { distanceToBox($0, o.box) < 0.3 * L } ?? false
                })
        }
        let umbrellaOverhead = objects.contains { o in
            guard o.kind == .umbrella, let head = j[.nose] ?? midShoulder else { return false }
            return o.box.center.y < head.y && abs(o.box.center.x - box.center.x) < box.width
        }
        let riding: (ObjectKind) -> Bool = { kind in
            holds([kind], point: midHip) || holds([kind], point: j[.leftKnee]) || holds([kind], point: j[.rightKnee])
        }

        let action: ObjectAction
        if near([.phone], [.leftEar, .rightEar], within: 0.5) {
            action = .calling
        } else if near([.phone], [.leftWrist, .rightWrist], within: 0.6) {
            action = .usingPhone
        } else if near([.cup, .bottle, .wineGlass], [.nose], within: 0.6) {
            action = .drinking
        } else if laptopInReach {
            action = .usingLaptop
        } else if near([.book], [.leftWrist, .rightWrist], within: 0.6) {
            action = .reading
        } else if riding(.bicycle) {
            action = .cycling
        } else if riding(.motorcycle) {
            action = .motorbiking
        } else if posture == .lying && (holds([.bed], point: midHip) || holds([.bed], point: midShoulder)) {
            action = .lyingBed
        } else if posture == .sitting && holds([.couch], point: midHip, grow: 0.2) {
            action = .sittingSofa
        } else if posture == .sitting && onSeat {
            action = .sittingChair
        } else if umbrellaOverhead {
            action = .umbrella
        } else if near([.ball], [.leftWrist, .rightWrist, .leftAnkle, .rightAnkle], within: 0.8) {
            action = .playingBall
        } else {
            action = .none
        }

        var carrying: [Carry] = []
        if let torsoBox = Rect.bounding([Joint.leftShoulder, .rightShoulder, .leftHip, .rightHip].compactMap { j[$0] }) {
            if objects.contains(where: { $0.kind == .backpack && overlaps($0.box, torsoBox) }) { carrying.append(.backpack) }
            if objects.contains(where: { $0.kind == .handbag && overlaps($0.box, torsoBox) }) { carrying.append(.handbag) }
        }

        return ActivityFrame(posture: posture, motion: motion, gesture: gesture, facing: facing,
                             objectAction: action, carrying: carrying)
    }

    // MARK: Pieces

    static func postureOf(_ j: [Joint: Vec2], midShoulder: Vec2?, midHip: Vec2?, L: Float) -> Posture {
        guard let s = midShoulder, let h = midHip else { return .standing }
        let torsoAngle = angleFromVertical(s - h, up: true)
        if torsoAngle > 60 { return .lying }

        let thighs: [(hip: Vec2, knee: Vec2)] = [(Joint.leftHip, Joint.leftKnee), (.rightHip, .rightKnee)].compactMap { pair in
            guard let hip = j[pair.0], let knee = j[pair.1] else { return nil }
            return (hip, knee)
        }
        let thighAngles = thighs.map { angleFromVertical($0.knee - $0.hip, up: false) }

        if torsoAngle > 30 {
            let legsStraight = !thighAngles.isEmpty && thighAngles.allSatisfy { $0 < 30 }
            return legsStraight ? .bending : .sitting
        }

        let horizontalThigh = thighAngles.contains { $0 > 50 }
        let foreshortened = thighs.contains { $0.knee.y > $0.hip.y && distance($0.knee, $0.hip) < 0.5 * L }
        guard horizontalThigh || foreshortened else { return .standing }

        let ankles = [j[.leftAnkle], j[.rightAnkle]].compactMap { $0 }
        if !ankles.isEmpty, ankles.allSatisfy({ $0.y - h.y < 0.8 * L }) { return .squatting }
        return .sitting
    }

    static func gestureOf(_ j: [Joint: Vec2], L: Float) -> GestureKind {
        func raised(_ wrist: Joint, _ shoulder: Joint) -> Bool {
            guard let w = j[wrist] else { return false }
            if let nose = j[.nose] { return w.y < nose.y }
            guard let s = j[shoulder] else { return false }
            return w.y < s.y - 0.3 * L
        }
        let raisedCount = [raised(.leftWrist, .leftShoulder), raised(.rightWrist, .rightShoulder)].filter { $0 }.count
        if raisedCount == 2 { return .raiseBoth }
        if raisedCount == 1 { return .raiseOne }

        guard let ls = j[.leftShoulder], let rs = j[.rightShoulder], let lw = j[.leftWrist], let rw = j[.rightWrist] else {
            return .none
        }
        let hipY = mid(j[.leftHip], j[.rightHip])?.y ?? (max(ls.y, rs.y) + L)
        let shoulderY = min(ls.y, rs.y)
        let minX = min(ls.x, rs.x) - 0.1 * L, maxX = max(ls.x, rs.x) + 0.1 * L
        let inFront = [lw, rw].allSatisfy { $0.x >= minX && $0.x <= maxX && $0.y >= shoulderY && $0.y <= hipY }
        let crossed = (lw.x - rw.x) * (ls.x - rs.x) < 0
        if inFront && crossed && distance(lw, rw) < 0.6 * L { return .armsCrossed }

        func onHip(_ wrist: Vec2, _ hip: Joint, _ elbow: Joint, _ shoulder: Vec2, outward: Float) -> Bool {
            guard let h = j[hip], let e = j[elbow] else { return false }
            return distance(wrist, h) < 0.3 * L && (e.x - shoulder.x) * outward > 0.15 * L
        }
        let leftOut: Float = ls.x >= rs.x ? 1 : -1
        if onHip(lw, .leftHip, .leftElbow, ls, outward: leftOut) && onHip(rw, .rightHip, .rightElbow, rs, outward: -leftOut) {
            return .handsOnHips
        }
        return .none
    }

    static func facingOf(_ j: [Joint: Vec2], L: Float) -> Facing {
        let shouldersReversed = j[.leftShoulder].flatMap { l in j[.rightShoulder].map { r in l.x < r.x - 0.05 * L } } ?? false
        if let nose = j[.nose], let le = j[.leftEye], let re = j[.rightEye],
           nose.x > min(le.x, re.x), nose.x < max(le.x, re.x), !shouldersReversed {
            return .toward
        }
        let faceHidden = j[.nose] == nil && j[.leftEye] == nil && j[.rightEye] == nil
        let bothShoulders = j[.leftShoulder] != nil && j[.rightShoulder] != nil
        if bothShoulders && (faceHidden || (shouldersReversed && j[.nose] == nil)) { return .away }
        return .side
    }

    // MARK: Geometry

    static func mid(_ a: Vec2?, _ b: Vec2?) -> Vec2? {
        guard let a, let b else { return nil }
        return (a + b) / 2
    }

    static func distance(_ a: Vec2, _ b: Vec2) -> Float {
        let d = a - b
        return (d * d).sum().squareRoot()
    }

    /// Angle in degrees between `v` and straight up (or straight down) in image space.
    static func angleFromVertical(_ v: Vec2, up: Bool) -> Float {
        let len = (v * v).sum().squareRoot()
        guard len > 0 else { return 0 }
        let cosine = (up ? -v.y : v.y) / len
        return acosf(min(max(cosine, -1), 1)) * 180 / .pi
    }

    /// 0 inside the box, else the distance to its nearest edge.
    static func distanceToBox(_ p: Vec2, _ r: Rect) -> Float {
        let dx = max(r.x - p.x, 0, p.x - (r.x + r.width))
        let dy = max(r.y - p.y, 0, p.y - r.maxY)
        return (dx * dx + dy * dy).squareRoot()
    }

    static func overlaps(_ a: Rect, _ b: Rect) -> Bool {
        a.x < b.x + b.width && b.x < a.x + a.width && a.y < b.maxY && b.y < a.maxY
    }
}
