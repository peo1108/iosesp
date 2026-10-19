import Testing
@testable import ESPCore

/// Upright, facing-the-camera standing skeleton. Torso length L = 0.2 (shoulders y 0.3, hips y 0.5).
/// The person's left side appears on the image's right.
func standingSkeleton() -> [Joint: Vec2] {
    [
        .nose: Vec2(0.5, 0.22), .leftEye: Vec2(0.52, 0.21), .rightEye: Vec2(0.48, 0.21),
        .leftEar: Vec2(0.54, 0.22), .rightEar: Vec2(0.46, 0.22),
        .leftShoulder: Vec2(0.56, 0.3), .rightShoulder: Vec2(0.44, 0.3),
        .leftElbow: Vec2(0.6, 0.42), .rightElbow: Vec2(0.4, 0.42),
        .leftWrist: Vec2(0.62, 0.55), .rightWrist: Vec2(0.38, 0.55),
        .leftHip: Vec2(0.54, 0.5), .rightHip: Vec2(0.46, 0.5),
        .leftKnee: Vec2(0.54, 0.7), .rightKnee: Vec2(0.46, 0.7),
        .leftAnkle: Vec2(0.54, 0.9), .rightAnkle: Vec2(0.46, 0.9),
    ]
}

func sittingSkeleton() -> [Joint: Vec2] {
    var s = standingSkeleton()
    s[.leftKnee] = Vec2(0.66, 0.52); s[.rightKnee] = Vec2(0.58, 0.52)
    s[.leftAnkle] = Vec2(0.66, 0.72); s[.rightAnkle] = Vec2(0.58, 0.72)
    return s
}

private let personBox = Rect(x: 0.36, y: 0.18, width: 0.28, height: 0.74)

private func evaluate(_ joints: [Joint: Vec2], speed: Float = 0, objects: [DetectedObject] = []) -> ActivityFrame {
    ActivityRules.evaluate(joints: joints, box: personBox, speed: speed, objects: objects)
}

private func object(_ kind: ObjectKind, at p: Vec2, size: Float = 0.04) -> DetectedObject {
    DetectedObject(kind: kind, box: Rect(x: p.x - size / 2, y: p.y - size / 2, width: size, height: size), confidence: 0.8)
}

// MARK: Motion

@Test func standingStill() {
    let f = evaluate(standingSkeleton(), speed: 0.1)
    #expect(f.posture == .standing && f.motion == .still && f.gesture == .none && f.objectAction == .none)
}

@Test func walking() { #expect(evaluate(standingSkeleton(), speed: 1.0).motion == .walking) }
@Test func running() { #expect(evaluate(standingSkeleton(), speed: 2.5).motion == .running) }

// MARK: Posture

@Test func sittingByHorizontalThigh() { #expect(evaluate(sittingSkeleton()).posture == .sitting) }

@Test func sittingForeshortenedThigh() {
    var s = standingSkeleton()
    s[.leftKnee] = Vec2(0.54, 0.56); s[.rightKnee] = Vec2(0.46, 0.56)
    s[.leftAnkle] = Vec2(0.54, 0.76); s[.rightAnkle] = Vec2(0.46, 0.76)
    #expect(evaluate(s).posture == .sitting)
}

@Test func squatting() {
    var s = standingSkeleton()
    for j in [Joint.nose, .leftEye, .rightEye, .leftEar, .rightEar, .leftShoulder, .rightShoulder, .leftElbow, .rightElbow,
              .leftWrist, .rightWrist, .leftHip, .rightHip] {
        s[j] = s[j]! + Vec2(0, 0.12)   // whole upper body drops: hips at 0.62
    }
    s[.leftKnee] = Vec2(0.6, 0.66); s[.rightKnee] = Vec2(0.4, 0.66)
    s[.leftAnkle] = Vec2(0.55, 0.76); s[.rightAnkle] = Vec2(0.45, 0.76)
    #expect(evaluate(s).posture == .squatting)
}

@Test func squatOnAChairCountsAsSitting() {
    var s = standingSkeleton()
    for j in [Joint.nose, .leftEye, .rightEye, .leftEar, .rightEar, .leftShoulder, .rightShoulder, .leftElbow, .rightElbow,
              .leftWrist, .rightWrist, .leftHip, .rightHip] {
        s[j] = s[j]! + Vec2(0, 0.12)
    }
    s[.leftKnee] = Vec2(0.6, 0.66); s[.rightKnee] = Vec2(0.4, 0.66)
    s[.leftAnkle] = Vec2(0.55, 0.76); s[.rightAnkle] = Vec2(0.45, 0.76)
    let chair = DetectedObject(kind: .chair, box: Rect(x: 0.4, y: 0.55, width: 0.2, height: 0.3), confidence: 0.8)
    let f = evaluate(s, objects: [chair])
    #expect(f.posture == .sitting && f.objectAction == .sittingChair)
}

@Test func lying() {
    var s = standingSkeleton()
    s[.leftShoulder] = Vec2(0.3, 0.6); s[.rightShoulder] = Vec2(0.3, 0.64)
    s[.leftHip] = Vec2(0.5, 0.6); s[.rightHip] = Vec2(0.5, 0.64)
    s[.leftKnee] = Vec2(0.7, 0.6); s[.rightKnee] = Vec2(0.7, 0.64)
    #expect(evaluate(s).posture == .lying)
}

@Test func bending() {
    var s = standingSkeleton()
    s[.leftShoulder] = Vec2(0.70, 0.36); s[.rightShoulder] = Vec2(0.58, 0.36)  // torso tipped ~45° forward
    #expect(evaluate(s).posture == .bending)
}

// MARK: Hands

@Test func raiseOneHand() {
    var s = standingSkeleton()
    s[.leftWrist] = Vec2(0.6, 0.1)
    #expect(evaluate(s).gesture == .raiseOne)
}

@Test func raiseBothHands() {
    var s = standingSkeleton()
    s[.leftWrist] = Vec2(0.6, 0.1); s[.rightWrist] = Vec2(0.4, 0.1)
    #expect(evaluate(s).gesture == .raiseBoth)
}

@Test func armsCrossed() {
    var s = standingSkeleton()
    s[.leftWrist] = Vec2(0.46, 0.42); s[.rightWrist] = Vec2(0.54, 0.42)
    #expect(evaluate(s).gesture == .armsCrossed)
}

@Test func handsOnHips() {
    var s = standingSkeleton()
    s[.leftWrist] = Vec2(0.55, 0.5); s[.rightWrist] = Vec2(0.45, 0.5)
    s[.leftElbow] = Vec2(0.66, 0.42); s[.rightElbow] = Vec2(0.34, 0.42)
    #expect(evaluate(s).gesture == .handsOnHips)
}

// MARK: Facing

@Test func facingToward() { #expect(evaluate(standingSkeleton()).facing == .toward) }

@Test func facingAway() {
    var s = standingSkeleton()
    for j in [Joint.nose, .leftEye, .rightEye, .leftEar, .rightEar] { s[j] = nil }
    s[.leftShoulder] = Vec2(0.44, 0.3); s[.rightShoulder] = Vec2(0.56, 0.3)
    #expect(evaluate(s).facing == .away)
}

@Test func facingSide() {
    var s = standingSkeleton()
    s[.rightEye] = nil; s[.rightEar] = nil
    #expect(evaluate(s).facing == .side)
}

// MARK: Objects

@Test func callingWithPhoneAtEar() {
    #expect(evaluate(standingSkeleton(), objects: [object(.phone, at: Vec2(0.55, 0.22))]).objectAction == .calling)
}

@Test func usingPhoneInHand() {
    #expect(evaluate(standingSkeleton(), objects: [object(.phone, at: Vec2(0.62, 0.56))]).objectAction == .usingPhone)
}

@Test func phoneFarAwayMeansNothing() {
    #expect(evaluate(standingSkeleton(), objects: [object(.phone, at: Vec2(0.95, 0.95))]).objectAction == .none)
}

@Test func drinking() {
    #expect(evaluate(standingSkeleton(), objects: [object(.cup, at: Vec2(0.5, 0.25))]).objectAction == .drinking)
}

@Test func sittingOnChair() {
    let chair = DetectedObject(kind: .chair, box: Rect(x: 0.4, y: 0.45, width: 0.25, height: 0.3), confidence: 0.8)
    let f = evaluate(sittingSkeleton(), objects: [chair])
    #expect(f.posture == .sitting && f.objectAction == .sittingChair)
}

@Test func usingLaptopWhileSitting() {
    let laptop = DetectedObject(kind: .laptop, box: Rect(x: 0.55, y: 0.5, width: 0.15, height: 0.1), confidence: 0.8)
    #expect(evaluate(sittingSkeleton(), objects: [laptop]).objectAction == .usingLaptop)
}

@Test func cycling() {
    let bike = DetectedObject(kind: .bicycle, box: Rect(x: 0.3, y: 0.45, width: 0.4, height: 0.5), confidence: 0.8)
    #expect(evaluate(standingSkeleton(), speed: 3, objects: [bike]).objectAction == .cycling)
}

@Test func umbrellaOverHead() {
    let umbrella = DetectedObject(kind: .umbrella, box: Rect(x: 0.35, y: 0.0, width: 0.3, height: 0.12), confidence: 0.8)
    #expect(evaluate(standingSkeleton(), objects: [umbrella]).objectAction == .umbrella)
}

@Test func carryingBackpack() {
    let bag = DetectedObject(kind: .backpack, box: Rect(x: 0.42, y: 0.3, width: 0.16, height: 0.2), confidence: 0.8)
    #expect(evaluate(standingSkeleton(), objects: [bag]).carrying == [.backpack])
}

// MARK: Main label

@Test func mainLabelPriority() {
    let phoneSitting = ActivityFrame(posture: .sitting, motion: .still, gesture: .raiseOne, facing: .toward,
                                     objectAction: .usingPhone, carrying: [])
    #expect(phoneSitting.main.text == "Dùng điện thoại" && phoneSitting.main.emoji == "📱")
    var f = phoneSitting
    f.objectAction = .none
    #expect(f.main.text == "Giơ tay")
    f.gesture = .none
    #expect(f.main.text == "Ngồi")
    f.posture = .standing
    #expect(f.main.text == "Đứng yên")
    f.motion = .walking
    #expect(f.main.text == "Đi bộ" && f.main.emoji == "🚶")
}

@Test func missingTorsoDefaultsToStanding() {
    let f = evaluate([.nose: Vec2(0.5, 0.2)], speed: 1)
    #expect(f.posture == .standing && f.motion == .walking)
}
