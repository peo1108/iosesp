import ARKit
import ESPCore
import UIKit

/// Converts captured-image and world coordinates into view points for one display frame.
///
/// Everything goes through ESPCore's `ViewMapping` (aspect fill, 180° in landscapeLeft) and plain pinhole
/// projection with the camera intrinsics — not ARKit's `displayTransform`/`projectPoint`, which rotate the
/// result 90° whenever the orientation passed in isn't a landscape one.
struct ScreenMapper {
    let viewSize: CGSize
    let orientation: UIInterfaceOrientation
    let camera: ARCamera
    let cameraToWorld: Mat4
    private let intrinsics: CameraIntrinsics
    private let mapping: ViewMapping

    init(frame: ARFrame, viewSize: CGSize, orientation: UIInterfaceOrientation) {
        self.viewSize = viewSize
        self.orientation = orientation
        camera = frame.camera
        cameraToWorld = Mat4(frame.camera.transform)
        intrinsics = CameraIntrinsics(frame.camera)
        mapping = ViewMapping(imageSize: intrinsics.imageSize,
                              viewSize: Vec2(Float(viewSize.width), Float(viewSize.height)),
                              upsideDown: orientation == .landscapeLeft)
    }

    /// Maps the unit square of the captured image onto the view (a 180° turn in landscapeLeft).
    var normalizedImageToView: CGAffineTransform {
        let t = mapping.affine
        return CGAffineTransform(a: CGFloat(t.a), b: 0, c: 0, d: CGFloat(t.d), tx: CGFloat(t.tx), ty: CGFloat(t.ty))
    }

    func point(normalized p: Vec2) -> CGPoint {
        cg(mapping.view(fromNormalized: p))
    }

    func rect(_ r: Rect) -> CGRect {
        let a = point(normalized: Vec2(r.x, r.y))
        let b = point(normalized: Vec2(r.x + r.width, r.maxY))
        return CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
    }

    /// Distance in front of the camera (negative when behind).
    func depth(of world: Vec3) -> Float {
        -SpatialMath.cameraSpace(world: world, cameraToWorld: cameraToWorld).z
    }

    func point(world: Vec3) -> CGPoint? {
        SpatialMath.project(world: world, intrinsics: intrinsics, cameraToWorld: cameraToWorld).map { cg(mapping.view(fromPixel: $0)) }
    }

    /// Plain pinhole projection that keeps going for points behind the camera (they come out mirrored),
    /// which is what edge arrows need. Never nil.
    func naivePoint(world: Vec3) -> CGPoint {
        let k = intrinsics
        let c = SpatialMath.cameraSpace(world: world, cameraToWorld: cameraToWorld)
        var depth = -c.z
        if abs(depth) < 0.01 { depth = depth < 0 ? -0.01 : 0.01 }
        let u = (k.fx * c.x / depth + k.cx) / k.imageSize.x
        let v = (-k.fy * c.y / depth + k.cy) / k.imageSize.y
        return point(normalized: Vec2(u, v))
    }

    /// The same projections through another camera (the one a detection was made with), on this view.
    func depth(of world: Vec3, camera other: ARCamera) -> Float {
        -SpatialMath.cameraSpace(world: world, cameraToWorld: Mat4(other.transform)).z
    }

    func point(world: Vec3, camera other: ARCamera) -> CGPoint? {
        SpatialMath.project(world: world, intrinsics: CameraIntrinsics(other), cameraToWorld: Mat4(other.transform))
            .map { cg(mapping.view(fromPixel: $0)) }
    }

    private func cg(_ v: Vec2) -> CGPoint {
        CGPoint(x: CGFloat(v.x), y: CGFloat(v.y))
    }
}

enum InterfaceOrientation {
    @MainActor private static var scene: UIWindowScene? {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
    }

    /// Always a landscape orientation (the app is landscape-only): anything else the system reports
    /// (portrait, unknown) counts as landscapeRight.
    @MainActor static var current: UIInterfaceOrientation {
        landscape(scene?.effectiveGeometry.interfaceOrientation)
    }

    static func landscape(_ o: UIInterfaceOrientation?) -> UIInterfaceOrientation {
        o == .landscapeLeft ? .landscapeLeft : .landscapeRight
    }

    @MainActor static var safeAreaInsets: UIEdgeInsets {
        scene?.keyWindow?.safeAreaInsets ?? UIEdgeInsets(top: 0, left: 59, bottom: 21, right: 59)
    }

    /// In landscapeRight the top of the phone (and its Dynamic Island) is on the left.
    @MainActor static var islandOnLeading: Bool {
        current != .landscapeLeft
    }
}
