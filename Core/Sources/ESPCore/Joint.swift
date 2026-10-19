/// The 19 body joints Vision's body-pose request reports.
public enum Joint: String, CaseIterable, Sendable, Codable {
    case nose, leftEye, rightEye, leftEar, rightEar
    case neck, leftShoulder, rightShoulder, leftElbow, rightElbow, leftWrist, rightWrist
    case root, leftHip, rightHip, leftKnee, rightKnee, leftAnkle, rightAnkle

    /// Skeleton edges drawn by the ESP.
    public static let bones: [(Joint, Joint)] = [
        (.nose, .neck),
        (.neck, .leftShoulder), (.neck, .rightShoulder),
        (.leftShoulder, .leftElbow), (.rightShoulder, .rightElbow),
        (.leftElbow, .leftWrist), (.rightElbow, .rightWrist),
        (.neck, .root),
        (.root, .leftHip), (.root, .rightHip),
        (.leftHip, .leftKnee), (.rightHip, .rightKnee),
        (.leftKnee, .leftAnkle), (.rightKnee, .rightAnkle),
        (.nose, .leftEye), (.nose, .rightEye),
        (.leftEye, .leftEar), (.rightEye, .rightEar),
    ]
}
