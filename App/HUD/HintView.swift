import SwiftUI

/// First-launch hint for the hidden menu gesture. Shown once, fades after 3 s.
struct HintView: View {
    var onDone: () -> Void
    @State private var visible = true

    var body: some View {
        if visible {
            Label("Chạm 2 lần bằng 3 ngón để mở menu", systemImage: "hand.tap")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .glassEffect(.regular, in: .capsule)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                .task {
                    try? await Task.sleep(for: .seconds(3))
                    withAnimation(.easeOut(duration: 0.5)) { visible = false }
                    onDone()
                }
        }
    }
}
