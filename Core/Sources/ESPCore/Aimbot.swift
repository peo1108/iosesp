/// Picks the fake aimbot's target: the aim point nearest the crosshair inside the FOV circle.
public enum Aimbot {
    public static func selectTarget(_ candidates: [(id: Int, aimPoint: Vec2)], center: Vec2, fovRadius: Float) -> Int? {
        var best: (id: Int, distance: Float)?
        for c in candidates {
            let d = c.aimPoint - center
            let distance = (d * d).sum().squareRoot()
            if distance <= fovRadius, distance < (best?.distance ?? .infinity) {
                best = (c.id, distance)
            }
        }
        return best?.id
    }
}
