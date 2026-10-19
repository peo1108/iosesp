import SwiftUI

struct WatermarkView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.monospaced())
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .glassEffect(.regular, in: .capsule)
            .opacity(0.8)
    }
}
