import ARKit
import ESPCore

/// Places Vision detections in the world using the LiDAR depth map (or a height-based estimate without it).
struct SpatialResolver {
    func resolve(_ raw: [RawDetection], frame: ARFrame) -> [Detection] {
        let intrinsics = CameraIntrinsics(frame.camera)
        let cameraToWorld = Mat4(frame.camera.transform)
        let depth = DepthReader(frame.smoothedSceneDepth ?? frame.sceneDepth)
        defer { depth?.unlock() }
        return raw.map { resolve($0, intrinsics: intrinsics, cameraToWorld: cameraToWorld, depth: depth) }
    }

    private func resolve(_ person: RawDetection, intrinsics k: CameraIntrinsics, cameraToWorld: Mat4, depth: DepthReader?) -> Detection {
        let box = person.box
        let size = k.imageSize
        func pixel(_ p: Vec2) -> Vec2 { p * size }

        let torso = Rect.bounding([Joint.leftShoulder, .rightShoulder, .neck, .leftHip, .rightHip].compactMap { person.joints[$0] })
            .flatMap { $0.width > 0.01 && $0.height > 0.01 ? $0 : nil }
            ?? Rect(x: box.x + 0.4 * box.width, y: box.y + 0.3 * box.height, width: 0.2 * box.width, height: 0.2 * box.height)

        let measured = depth?.median(over: torso, grid: 5)
        let estimated = measured == nil
        let d = measured ?? SpatialMath.estimatedDistance(boxHeightPixels: box.height * size.y, fy: k.fy)

        let clippedTop = box.y < 0.02, clippedBottom = box.maxY > 0.98
        var height: Float = 1.70
        if !clippedTop && !clippedBottom {
            let top = SpatialMath.unproject(pixel: pixel(Vec2(box.center.x, box.y)), depth: d, intrinsics: k, cameraToWorld: cameraToWorld)
            let bottom = SpatialMath.unproject(pixel: pixel(Vec2(box.center.x, box.maxY)), depth: d, intrinsics: k, cameraToWorld: cameraToWorld)
            height = min(max(abs(top.y - bottom.y), 1.0), 2.2)
        }

        let base: Vec3
        if clippedBottom {
            // Feet are out of frame: drop from the torso to roughly floor level instead.
            let torsoPoint = SpatialMath.unproject(pixel: pixel(torso.center), depth: d, intrinsics: k, cameraToWorld: cameraToWorld)
            base = torsoPoint - Vec3(0, height * 0.58, 0)
        } else {
            base = SpatialMath.unproject(pixel: pixel(Vec2(box.center.x, box.maxY)), depth: d, intrinsics: k, cameraToWorld: cameraToWorld)
        }

        let yaw: Float
        if let l = person.joints[.leftShoulder], let r = person.joints[.rightShoulder] {
            let dl = depth?.median(over: Rect(x: l.x - 0.01, y: l.y - 0.01, width: 0.02, height: 0.02), grid: 3) ?? d
            let dr = depth?.median(over: Rect(x: r.x - 0.01, y: r.y - 0.01, width: 0.02, height: 0.02), grid: 3) ?? d
            yaw = SpatialMath.yaw(
                leftShoulder: SpatialMath.unproject(pixel: pixel(l), depth: dl, intrinsics: k, cameraToWorld: cameraToWorld),
                rightShoulder: SpatialMath.unproject(pixel: pixel(r), depth: dr, intrinsics: k, cameraToWorld: cameraToWorld))
        } else {
            let toPerson = base - cameraToWorld.translation
            yaw = atan2f(toPerson.x, toPerson.z)
        }

        var occlusion = Occlusion.visible
        if let depth, !estimated, SpatialMath.isPartiallyOccluded(sampleDepths: depth.samples(over: box, grid: 6), personDepth: d) {
            occlusion = .partial
        }

        return Detection(box: box, joints: person.joints, worldPosition: base, distance: d,
                         distanceIsEstimated: estimated, heightMeters: height, yaw: yaw, occlusion: occlusion)
    }
}

/// Locked read access to an ARDepthData's Float32 depth map and UInt8 confidence map.
private final class DepthReader {
    private let depth: CVPixelBuffer
    private let confidence: CVPixelBuffer?
    private let width: Int, height: Int, depthRow: Int, confidenceRow: Int
    private let depthBase: UnsafeMutableRawPointer
    private let confidenceBase: UnsafeMutableRawPointer?

    init?(_ data: ARDepthData?) {
        guard let data else { return nil }
        depth = data.depthMap
        confidence = data.confidenceMap
        CVPixelBufferLockBaseAddress(depth, .readOnly)
        guard let base = CVPixelBufferGetBaseAddress(depth) else {
            CVPixelBufferUnlockBaseAddress(depth, .readOnly)
            return nil
        }
        depthBase = base
        width = CVPixelBufferGetWidth(depth)
        height = CVPixelBufferGetHeight(depth)
        depthRow = CVPixelBufferGetBytesPerRow(depth)
        if let confidence {
            CVPixelBufferLockBaseAddress(confidence, .readOnly)
            confidenceBase = CVPixelBufferGetBaseAddress(confidence)
            confidenceRow = CVPixelBufferGetBytesPerRow(confidence)
        } else {
            confidenceBase = nil
            confidenceRow = 0
        }
    }

    func unlock() {
        CVPixelBufferUnlockBaseAddress(depth, .readOnly)
        if let confidence { CVPixelBufferUnlockBaseAddress(confidence, .readOnly) }
    }

    /// Value at a normalized image point (the depth map is aligned with the captured image).
    func sample(_ p: Vec2) -> (depth: Float, confidence: UInt8) {
        let x = min(max(Int(p.x * Float(width)), 0), width - 1)
        let y = min(max(Int(p.y * Float(height)), 0), height - 1)
        let d = depthBase.advanced(by: y * depthRow).assumingMemoryBound(to: Float32.self)[x]
        let c = confidenceBase?.advanced(by: y * confidenceRow).assumingMemoryBound(to: UInt8.self)[x] ?? 2
        return (d, c)
    }

    func samples(over r: Rect, grid n: Int) -> [Float] {
        gridPoints(r, n).map { sample($0).depth }
    }

    func median(over r: Rect, grid n: Int) -> Float? {
        let values = gridPoints(r, n).map(sample)
        return SpatialMath.medianDepth(values.map(\.depth), confidences: values.map(\.confidence))
    }

    private func gridPoints(_ r: Rect, _ n: Int) -> [Vec2] {
        var points: [Vec2] = []
        for i in 0..<n {
            for j in 0..<n {
                let fx = (Float(i) + 0.5) / Float(n), fy = (Float(j) + 0.5) / Float(n)
                points.append(Vec2(r.x + fx * r.width, r.y + fy * r.height))
            }
        }
        return points
    }
}
