public typealias Vec2 = SIMD2<Float>
public typealias Vec3 = SIMD3<Float>
public typealias Vec4 = SIMD4<Float>

public func dot(_ a: Vec3, _ b: Vec3) -> Float { (a * b).sum() }

public func length(_ v: Vec3) -> Float { dot(v, v).squareRoot() }

public func normalize(_ v: Vec3) -> Vec3 {
    let l = length(v)
    return l > 0 ? v / l : v
}
