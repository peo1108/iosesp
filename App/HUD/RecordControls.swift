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
