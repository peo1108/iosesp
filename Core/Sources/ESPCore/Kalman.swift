/// Constant-velocity Kalman filter, one independent (position, velocity) filter per SIMD lane.
///
/// `processNoise` is the white-noise acceleration density (units²/s³): higher follows turns faster.
/// `measurementNoise` is the variance of one measurement (units²).
public struct KalmanCV<V: SIMD & Sendable>: Sendable where V.Scalar == Float {
    public private(set) var position: V
    public private(set) var velocity: V
    private var p00: V, p01: V, p11: V
    private let q: Float
    private let r: Float

    public init(position: V, processNoise: Float, measurementNoise: Float, initialVelocityVariance: Float = 1) {
        self.position = position
        velocity = .zero
        p00 = V(repeating: measurementNoise)
        p01 = .zero
        p11 = V(repeating: initialVelocityVariance)
        q = processNoise
        r = measurementNoise
    }

    public mutating func predict(dt: Float) {
        guard dt > 0 else { return }
        position += velocity * dt
        let dt2 = dt * dt
        p00 += (p01 * (2 * dt)) + (p11 * dt2) + V(repeating: q * dt2 * dt / 3)
        p01 += (p11 * dt) + V(repeating: q * dt2 / 2)
        p11 += V(repeating: q * dt)
    }

    public mutating func update(_ z: V) {
        let innovation = z - position
        let s = p00 + V(repeating: r)
        let k0 = p00 / s, k1 = p01 / s
        position += k0 * innovation
        velocity += k1 * innovation
        let one = V(repeating: 1)
        p11 -= k1 * p01
        p01 *= (one - k0)
        p00 *= (one - k0)
    }
}
