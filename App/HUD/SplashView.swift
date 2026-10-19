import SwiftUI

/// ~2 s fake "injector" boot screen on cold launch. Tap to skip.
struct SplashView: View {
    let accent: Color
    var onFinish: () -> Void

    @State private var lines = 0
    @State private var progress: CGFloat = 0
    @State private var glow = false

    private let steps = ["Injecting…", "Bypassing anti-cheat…", "Loading offsets…"]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 22) {
                Image(systemName: "scope")
                    .font(.system(size: 64, weight: .semibold))
                    .foregroundStyle(accent)
                    .shadow(color: accent.opacity(glow ? 0.9 : 0.3), radius: glow ? 24 : 10)

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(0..<steps.count, id: \.self) { i in
                        HStack(spacing: 8) {
                            Text(steps[i])
                            Spacer(minLength: 12)
                            Text("✓").foregroundStyle(Palette.visible)
                        }
                        .opacity(i < lines ? 1 : 0)
                        .offset(y: i < lines ? 0 : 6)
                    }
                }
                .font(.system(.callout, design: .monospaced))
                .frame(width: 300)

                Capsule()
                    .fill(accent)
                    .frame(width: 260 * progress, height: 6)
                    .frame(width: 260, height: 6, alignment: .leading)
                    .padding(3)
                    .glassEffect(.regular, in: .capsule)
            }
        }
        .contentShape(.rect)
        .onTapGesture(perform: onFinish)
        .task {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { glow = true }
            withAnimation(.linear(duration: 2)) { progress = 1 }
            for _ in steps {
                try? await Task.sleep(for: .milliseconds(450))
                withAnimation(.spring(duration: 0.3)) { lines += 1 }
            }
            try? await Task.sleep(for: .milliseconds(650))
            onFinish()
        }
    }
}
