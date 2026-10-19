import Foundation

/// One Euro filter (Casiez et al.): heavy smoothing when still, low lag when moving fast.
/// Each SIMD lane is filtered independently.
public struct OneEuroFilter<V: SIMD & Sendable>: Sendable where V.Scalar == Float {
    public var minCutoff: Float
    public var beta: Float
    public var dCutoff: Float

    private var lastValue: V?
    private var lastDerivative: V = .zero
    private var lastTime: TimeInterval = 0

    public init(minCutoff: Float = 1.0, beta: Float = 0.02, dCutoff: Float = 1.0) {
        self.minCutoff = minCutoff
        self.beta = beta
        self.dCutoff = dCutoff
    }

    public mutating func filter(_ x: V, at t: TimeInterval) -> V {
        guard let previous = lastValue else {
            lastValue = x
            lastTime = t
            lastDerivative = .zero
            return x
        }
        let dt = Float(t - lastTime)
        guard dt > 0 else { return previous }

        let derivative = (x - previous) / dt
        let smoothedDerivative = lastDerivative + (derivative - lastDerivative) * Self.alpha(cutoff: dCutoff, dt: dt)

        var out = previous
        for i in out.indices {
            let cutoff = minCutoff + beta * abs(smoothedDerivative[i])
            out[i] = previous[i] + (x[i] - previous[i]) * Self.alpha(cutoff: cutoff, dt: dt)
        }
        lastValue = out
        lastDerivative = smoothedDerivative
        lastTime = t
        return out
    }

    public mutating func reset() {
        lastValue = nil
        lastDerivative = .zero
    }

    private static func alpha(cutoff: Float, dt: Float) -> Float {
        let tau = 1 / (2 * Float.pi * cutoff)
        return 1 / (1 + tau / dt)
    }
}
