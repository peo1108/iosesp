import ESPCore
import SwiftUI

/// The hidden mod menu: a compact Liquid Glass panel from the trailing edge. Camera on top, then grids of
/// toggle tiles like Control Center.
struct MenuPanel: View {
    @Bindable var store: SettingsStore
    var modelWarning = false
    var ultraWideMissing = false
    var onClose: () -> Void

    private var settings: Settings { store.settings }
    private var accent: Color { Palette.accent(settings.accent) }
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    cameraSection
                    section("ESP") {
                        grid {
                            tile("Box", "viewfinder", \.box)
                            tile("Thẻ chi tiết", "list.bullet.rectangle.portrait", \.detailCard)
                            tile("Mũi tên", "location.north.line.fill", \.offscreenArrows)
                            tile("Tia", "line.diagonal", \.snaplines)
                            tile("Con vật", "pawprint.fill", \.showAnimals)
                            boxStyleTile
                        }
                    }
                    section("HUD") {
                        grid {
                            tile("Bộ đếm", "person.3.fill", \.stats)
                            tile("Danh sách", "list.number", \.playerList)
                            tile("Nhật ký", "text.bubble.fill", \.eventLog)
                            tile("Watermark", "textformat", \.watermark)
                        }
                        if settings.watermark { watermarkField }
                    }
                    section("Quay video") {
                        grid {
                            tile("Nút quay", "record.circle", \.recordButton)
                            tile("Thu mic", "mic.fill", \.microphone)
                            tile("Rung", "iphone.radiowaves.left.and.right", \.haptics)
                        }
                    }
                    accentRow
                    footer
                }
                .padding(16)
            }
            .scrollIndicators(.hidden)
        }
        .tint(accent)
        .glassEffect(.regular, in: .rect(cornerRadius: 28))
        .sensoryFeedback(.selection, trigger: feedbackKey) { _, _ in settings.haptics }
    }

    /// Settings minus free text, so typing the watermark doesn't buzz on every key.
    private var feedbackKey: Settings {
        var s = settings
        s.watermarkText = ""
        return s
    }

    // MARK: Sections

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "scope")
                .font(.title2.weight(.semibold))
                .foregroundStyle(accent)
            VStack(alignment: .leading, spacing: 1) {
                Text("ESP").font(.headline)
                Text("v3.0 · Street").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.bold))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 4)
    }

    private var cameraSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Camera")
            Picker("Camera", selection: $store.settings.lens) {
                Text("1× Thường").tag(CameraLens.wide)
                Text("0.5× Siêu rộng").tag(CameraLens.ultraWide)
            }
            .pickerStyle(.segmented)
            if ultraWideMissing {
                note("Máy này không có camera góc siêu rộng — đang dùng 1×.", symbol: "exclamationmark.triangle.fill",
                     color: Palette.partial)
            } else if settings.lens == .ultraWide {
                note("Rộng gấp đôi nhưng không có LiDAR: khoảng cách là ước lượng (~), người ở xa nhỏ hơn.",
                     symbol: "info.circle", color: .secondary)
            }
        }
    }

    private var boxStyleTile: some View {
        let style = settings.boxStyle
        let (title, symbol): (String, String) = switch style {
        case .corner: ("Kiểu: Góc", "square.dashed")
        case .full: ("Kiểu: Viền", "square")
        case .glass: ("Kiểu: Kính", "square.fill")
        }
        return Button {
            let all = BoxStyle.allCases
            store.settings.boxStyle = all[(all.firstIndex(of: style)! + 1) % all.count]
        } label: {
            tileLabel(title, symbol, on: false)
        }
        .buttonStyle(.plain)
        .opacity(settings.box ? 1 : 0.4)
        .disabled(!settings.box)
    }

    private var watermarkField: some View {
        HStack(spacing: 10) {
            Image(systemName: "character.cursor.ibeam").foregroundStyle(accent)
            TextField("Chữ watermark", text: $store.settings.watermarkText)
                .textFieldStyle(.plain)
                .submitLabel(.done)
        }
        .font(.subheadline)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.07), in: .rect(cornerRadius: 14, style: .continuous))
        .padding(.top, 8)
    }

    private var accentRow: some View {
        HStack(spacing: 10) {
            ForEach(AccentName.allCases, id: \.self) { name in
                Button {
                    store.settings.accent = name
                } label: {
                    Circle()
                        .fill(Palette.accent(name))
                        .frame(width: 22, height: 22)
                        .overlay {
                            if settings.accent == name {
                                Circle().strokeBorder(.white, lineWidth: 2).padding(-4)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 4)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if modelWarning {
                note("Không tải được model YOLO — đang dùng nhận diện dự phòng, kém hơn và không có con vật.",
                     symbol: "exclamationmark.triangle.fill", color: Palette.partial)
            }
            Text("Chạm 2 lần bằng 3 ngón để mở/đóng menu. Giữ 3 ngón để quay video.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Building blocks

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle(title)
            content()
        }
    }

    private func grid<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        LazyVGrid(columns: columns, spacing: 8, content: content)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.leading, 4)
    }

    private func note(_ text: String, symbol: String, color: Color) -> some View {
        Label(text, systemImage: symbol)
            .font(.caption)
            .foregroundStyle(color)
    }

    private func tile(_ title: String, _ symbol: String, _ keyPath: WritableKeyPath<Settings, Bool>) -> some View {
        let on = settings[keyPath: keyPath]
        return Button {
            store.settings[keyPath: keyPath].toggle()
        } label: {
            tileLabel(title, symbol, on: on)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func tileLabel(_ title: String, _ symbol: String, on: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol).font(.body.weight(.semibold))
            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .foregroundStyle(on ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
        .background(on ? AnyShapeStyle(accent) : AnyShapeStyle(Color.white.opacity(0.07)),
                    in: .rect(cornerRadius: 16, style: .continuous))
        .contentShape(.rect(cornerRadius: 16))
        .animation(.easeInOut(duration: 0.15), value: on)
    }
}
