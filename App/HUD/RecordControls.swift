import SwiftUI

/// Camera-style shutter: glass ring, red dot that morphs to a rounded square while recording.
struct RecordButton: View {
    let isRecording: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: isRecording ? 6 : 22, style: .continuous)
                .fill(Palette.alert)
                .frame(width: isRecording ? 26 : 44, height: isRecording ? 26 : 44)
                .frame(width: 64, height: 64)
                .glassEffect(.regular.interactive(), in: .circle)
        }
        .buttonStyle(.plain)
        .animation(.spring(duration: 0.3, bounce: 0.2), value: isRecording)
    }
}

/// Small red glass dot shown at the top while recording.
struct RecordingDot: View {
    @State private var dim = false

    var body: some View {
        Circle()
            .fill(Palette.alert)
            .frame(width: 10, height: 10)
            .opacity(dim ? 0.4 : 1)
            .padding(6)
            .glassEffect(.regular, in: .circle)
            .onAppear { withAnimation(.easeInOut(duration: 0.8).repeatForever()) { dim = true } }
    }
}
