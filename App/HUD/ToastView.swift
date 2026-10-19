import SwiftUI

/// Bottom-center glass capsule for recording results.
struct ToastView: View {
    let event: ToastEvent
    var onRetry: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            switch event.kind {
            case .saved:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.visible)
                Text("Đã lưu vào Ảnh")
            case let .failed(message, canRetry):
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Palette.partial)
                Text(message)
                if canRetry {
                    Button("Thử lại", action: onRetry)
                        .buttonStyle(.glass)
                        .controlSize(.small)
                }
            }
        }
        .font(.subheadline.weight(.semibold))
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: .capsule)
    }
}
