import SwiftUI

/// A glass pill next to the real Dynamic Island that expands when the aimbot locks on.
struct FakeIslandView: View {
    /// Distance to the locked player, nil when nothing is locked.
    let lockedDistance: Float?
    let accent: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: lockedDistance == nil ? "scope" : "target")
                .font(.footnote.weight(.bold))
                .foregroundStyle(lockedDistance == nil ? accent : Palette.locked)
                .contentTransition(.symbolEffect(.replace))
            if let lockedDistance {
                Text("Locked · \(String(format: "%.1f", lockedDistance)) m")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .fixedSize()
                    .transition(.opacity.combined(with: .scale(scale: 0.8, anchor: .leading)))
            }
        }
        .frame(minWidth: 36, minHeight: 36)
        .padding(.horizontal, lockedDistance == nil ? 0 : 12)
        .glassEffect(.regular.tint(lockedDistance == nil ? .clear : Palette.locked.opacity(0.25)), in: .capsule)
        .animation(.spring(duration: 0.4, bounce: 0.25), value: lockedDistance == nil)
    }
}
