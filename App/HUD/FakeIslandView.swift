import SwiftUI

/// A glass pill next to the real Dynamic Island showing the nearest person.
struct FakeIslandView: View {
    /// e.g. "Người 02 · 1.8 m"; nil when nobody is in view.
    let text: String?
    let accent: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: text == nil ? "scope" : "person.fill")
                .font(.footnote.weight(.bold))
                .foregroundStyle(accent)
                .contentTransition(.symbolEffect(.replace))
            if let text {
                Text(text)
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .fixedSize()
                    .transition(.opacity.combined(with: .scale(scale: 0.8, anchor: .leading)))
            }
        }
        .frame(minWidth: 36, minHeight: 36)
        .padding(.horizontal, text == nil ? 0 : 12)
        .glassEffect(.regular.tint(text == nil ? .clear : accent.opacity(0.2)), in: .capsule)
        .animation(.spring(duration: 0.4, bounce: 0.25), value: text == nil)
    }
}
