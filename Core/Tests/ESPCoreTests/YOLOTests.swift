import Testing
@testable import ESPCore

private let input = Vec2(640, 480)

/// Builds a channel-first [56 × n] pose tensor; `anchors` maps anchor index → (box, conf, keypoints).
private func poseTensor(n: Int, anchors: [Int: (box: (Float, Float, Float, Float), conf: Float, kpts: [Int: (Float, Float, Float)])]) -> [Float] {
    var v = [Float](repeating: 0, count: 56 * n)
    func set(_ c: Int, _ i: Int, _ x: Float) { v[c * n + i] = x }
    for (i, a) in anchors {
        set(0, i, a.box.0); set(1, i, a.box.1); set(2, i, a.box.2); set(3, i, a.box.3)
        set(4, i, a.conf)
        for k in 0..<17 {
            let p = a.kpts[k] ?? (0, 0, 0.1)
            set(5 + 3 * k, i, p.0); set(6 + 3 * k, i, p.1); set(7 + 3 * k, i, p.2)
        }
    }
    return v
}

/// nose 0, leftShoulder 5, rightShoulder 6, leftHip 11, rightHip 12
private let person: (box: (Float, Float, Float, Float), conf: Float, kpts: [Int: (Float, Float, Float)]) = (
    (320, 240, 100, 300), 0.9,
    [0: (330, 120, 0.9), 5: (350, 170, 0.9), 6: (290, 170, 0.9), 11: (340, 280, 0.9), 12: (300, 280, 0.9)]
)

@Test func decodesSinglePerson() {
    let values = poseTensor(n: 3, anchors: [0: ((100, 100, 50, 50), 0.1, [:]), 1: person])
    let r = YOLO.decodePose(values, shape: [1, 56, 3], inputSize: input)
    #expect(r.count == 1)
    let c = r[0]
    #expect(abs(c.box.x - 270 / 640) < 1e-5 && abs(c.box.y - 90 / 480) < 1e-5)
    #expect(abs(c.box.width - 100 / 640) < 1e-5 && abs(c.box.height - 300 / 480) < 1e-5)
    #expect(c.confidence == 0.9)
    #expect(c.joints[.nose] == Vec2(330 / 640, 120 / 480))
    #expect(c.joints[.leftEye] == nil)
    #expect(c.joints[.neck] == Vec2(320 / 640, 170 / 480))
    #expect(c.joints[.root] == Vec2(320 / 640, 280 / 480))
}

@Test func decodesTransposedLayout() {
    let channelFirst = poseTensor(n: 3, anchors: [1: person])
    var rowMajor = [Float](repeating: 0, count: 56 * 3)
    for c in 0..<56 { for i in 0..<3 { rowMajor[i * 56 + c] = channelFirst[c * 3 + i] } }
    let r = YOLO.decodePose(rowMajor, shape: [1, 3, 56], inputSize: input)
    #expect(r.count == 1 && r[0].joints[.nose] == Vec2(330 / 640, 120 / 480))
}

@Test func dropsWeakBoxesAndOverlaps() {
    var twin = person
    twin.conf = 0.8
    twin.box.0 = 325
    let values = poseTensor(n: 4, anchors: [0: person, 1: twin, 2: ((100, 100, 50, 50), 0.2, [:])])
    let r = YOLO.decodePose(values, shape: [1, 56, 4], inputSize: input)
    #expect(r.count == 1 && r[0].confidence == 0.9)
}

@Test func rejectsUnexpectedShape() {
    #expect(YOLO.decodePose([1, 2, 3], shape: [1, 3], inputSize: input).isEmpty)
    #expect(YOLO.decodePose([Float](repeating: 0, count: 10), shape: [1, 5, 2], inputSize: input).isEmpty)
}

@Test func nmsKeepsBestOfOverlaps() {
    let boxes = [Rect(x: 0, y: 0, width: 1, height: 1), Rect(x: 0.05, y: 0, width: 1, height: 1), Rect(x: 2, y: 2, width: 1, height: 1)]
    #expect(YOLO.nms(boxes, scores: [0.9, 0.8, 0.7], iouThreshold: 0.5) == [0, 2])
    #expect(YOLO.nms(boxes, scores: [0.5, 0.95, 0.7], iouThreshold: 0.5) == [1, 2])
}

@Test func cocoLabels() {
    #expect(COCOClass(label: "dog") == .animal(.dog))
    #expect(COCOClass(label: "cell phone") == .object(.phone))
    #expect(COCOClass(label: "wine glass") == .object(.wineGlass))
    #expect(COCOClass(label: "sports ball") == .object(.ball))
    #expect(COCOClass(label: "person") == .person)
    #expect(COCOClass(label: "toaster") == .other)
    #expect(ObjectKind.phone.emoji == "📱" && ObjectKind.laptop.name == "Laptop")
}

@Test func topLeftMappingDown() {
    #expect(VisionMapping.topLeftPoint(Vec2(0.2, 0.3), orientation: .up) == Vec2(0.2, 0.3))
    #expect(VisionMapping.topLeftPoint(Vec2(0.2, 0.3), orientation: .down) == Vec2(0.8, 0.7))
    let r = VisionMapping.topLeftRect(Rect(x: 0.1, y: 0.2, width: 0.3, height: 0.4), orientation: .down)
    #expect(abs(r.x - 0.6) < 1e-6 && abs(r.y - 0.4) < 1e-6 && r.width == 0.3 && r.height == 0.4)
}

@Test func thermalBudgetsV3() {
    #expect(ThermalPolicy.budget(.nominal, isRecording: false)
            == PerceptionBudget(poseHz: 60, objectHz: 30, showHeatWarning: false, hudHz: 60))
    #expect(ThermalPolicy.budget(.fair, isRecording: false)
            == PerceptionBudget(poseHz: 30, objectHz: 15, showHeatWarning: false, hudHz: 60))
    #expect(ThermalPolicy.budget(.serious, isRecording: false)
            == PerceptionBudget(poseHz: 20, objectHz: 8, showHeatWarning: false, hudHz: 30))
    #expect(ThermalPolicy.budget(.critical, isRecording: false)
            == PerceptionBudget(poseHz: 12, objectHz: 4, showHeatWarning: true, hudHz: 30))
    let recording = ThermalPolicy.budget(.nominal, isRecording: true)
    #expect(recording.poseHz == 30 && recording.objectHz == 15)
    #expect(ThermalPolicy.budget(.critical, isRecording: true).poseHz == 12)
}
