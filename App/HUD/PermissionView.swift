import SwiftUI

struct PermissionView: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "camera.fill")
                .font(.system(size: 34, weight: .semibold))
            Text("Cần quyền camera")
                .font(.title3.weight(.bold))
            Text("Vào Cài đặt → ESP → bật Camera.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("Mở Cài đặt") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
            .buttonStyle(.glassProminent)
            .padding(.top, 4)
        }
        .padding(28)
        .glassEffect(.regular, in: .rect(cornerRadius: 28))
    }
}
