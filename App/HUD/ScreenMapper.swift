import ARKit
import ESPCore
import UIKit

/// Converts captured-image and world coordinates into view points for one display frame.
struct ScreenMapper {
    let viewSize: CGSize
    let orientation: UIInterfaceOrientation
    let camera: ARCamera
    let cameraToWorld: Mat4
    private let imageToView: CGAffineTransform

    init(frame: ARFrame, viewSize: CGSize, orientation: UIInterfaceOrientation) {
        self.viewSize = viewSize
        self.orientation = orientation
        camera = frame.camera
        cameraToWorld = Mat4(frame.camera.transform)
        imageToView = frame.displayTransform(for: orientation, viewportSize: viewSize)
    }

    /// Maps the unit square of the captured image onto the view (may include a 180° turn in landscapeLeft).
    var normalizedImageToView: CGAffineTransform {
        imageToView.concatenating(CGAffineTransform(scaleX: viewSize.width, y: viewSize.height))
    }

    /// Plain pinhole projection that keeps going for points behind the camera (they come out mirrored),
    /// which is what edge arrows need. Never nil.
    func naivePoint(world: Vec3) -> CGPoint {
        let k = CameraIntrinsics(camera)
        let c = SpatialMath.cameraSpace(world: world, cameraToWorld: cameraToWorld)
        var depth = -c.z
        if abs(depth) < 0.01 { depth = depth < 0 ? -0.01 : 0.01 }
        let u = (k.fx * c.x / depth + k.cx) / k.imageSize.x
        let v = (-k.fy * c.y / depth + k.cy) / k.imageSize.y
        return point(normalized: Vec2(u, v))
    }

    func point(normalized p: Vec2) -> CGPoint {
        let n = CGPoint(x: CGFloat(p.x), y: CGFloat(p.y)).applying(imageToView)
        return CGPoint(x: n.x * viewSize.width, y: n.y * viewSize.height)
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
        guard depth(of: world) > 0.01 else { return nil }
        return unclampedPoint(world: world)
    }

    /// Projection even for points behind the camera (used to aim off-screen arrows).
    func unclampedPoint(world: Vec3) -> CGPoint {
        camera.projectPoint(world, orientation: orientation, viewportSize: viewSize)
    }

    /// The same projections through another camera (the one a detection was made with), on this view.
    func depth(of world: Vec3, camera other: ARCamera) -> Float {
        -SpatialMath.cameraSpace(world: world, cameraToWorld: Mat4(other.transform)).z
    }

    func point(world: Vec3, camera other: ARCamera) -> CGPoint? {
        guard depth(of: world, camera: other) > 0.01 else { return nil }
        return other.projectPoint(world, orientation: orientation, viewportSize: viewSize)
    }
}

enum InterfaceOrientation {
    @MainActor private static var scene: UIWindowScene? {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
    }

    @MainActor static var current: UIInterfaceOrientation {
        scene?.effectiveGeometry.interfaceOrientation ?? .landscapeRight
    }

    @MainActor static var safeAreaInsets: UIEdgeInsets {
        scene?.keyWindow?.safeAreaInsets ?? UIEdgeInsets(top: 0, left: 59, bottom: 21, right: 59)
    }

    /// In landscapeRight the top of the phone (and its Dynamic Island) is on the left.
    @MainActor static var islandOnLeading: Bool {
        current != .landscapeLeft
    }
}
