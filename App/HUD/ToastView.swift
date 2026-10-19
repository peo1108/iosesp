import SwiftUI

/// Bottom-center glass capsule for recording results.
struct ToastView: View {
    let event: ToastEvent
    var onRetry: () -> Void
    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(spacing: 10) {
            switch event.kind {
            case .saved:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.visible)
                Text("Đã lưu vào Ảnh")
            case let .failed(message, action):
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Palette.partial)
                Text(message)
                switch action {
                case .retry:
                    Button("Thử lại", action: onRetry)
                        .buttonStyle(.glass)
                        .controlSize(.small)
                case .openSettings:
                    Button("Mở Cài đặt") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                case nil:
                    EmptyView()
                }
            }
        }
        .font(.subheadline.weight(.semibold))
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: .capsule)
    }
}
