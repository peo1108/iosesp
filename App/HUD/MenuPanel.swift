import ESPCore
import SwiftUI

/// The hidden mod menu: a Liquid Glass panel from the trailing edge, laid out like the Settings app.
struct MenuPanel: View {
    @Bindable var store: SettingsStore
    var modelWarning = false
    var onClose: () -> Void

    private var accent: Color { Palette.accent(store.settings.accent) }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    presetSection
                    section("Người") {
                        toggle("Box", "square.dashed", \.box)
                        picker("Kiểu box", "cube", \.boxStyle,
                               [(.corner, "Góc"), (.full, "Đầy đủ"), (.threeD, "3D"), (.glass, "Kính")])
                        toggle("Nhãn (Người 01)", "tag.fill", \.label)
                        toggle("Hành động", "figure.walk.motion", \.activity)
                        toggle("Thẻ chi tiết", "list.bullet.rectangle.portrait", \.detailCard)
                        toggle("Khoảng cách", "ruler", \.distance)
                        toggle("Skeleton", "figure.walk", \.skeleton)
                        toggle("Vòng đầu", "circle", \.headDot)
                        toggle("Vệt chân", "shoeprints.fill", \.trails)
                        toggle("Chams", "person.fill", \.chams)
                        toggle("Snaplines", "line.diagonal", \.snaplines)
                        toggle("Mũi tên ngoài màn hình", "location.north.line.fill", \.offscreenArrows)
                    }
                    section("Con vật & đồ vật") {
                        toggle("Hiện con vật", "pawprint.fill", \.showAnimals)
                        toggle("Hiện đồ vật", "iphone", \.showObjects)
                    }
                    section("HUD") {
                        toggle("Bộ đếm & FPS", "person.3.fill", \.stats)
                        toggle("Danh sách trong khung", "list.number", \.playerList)
                        toggle("Nhật ký sự kiện", "text.bubble.fill", \.eventLog)
                        toggle("Radar", "dot.radiowaves.left.and.right", \.radar)
                        slider("Tầm radar", "scope", \.radarRange, 5...30, "%.0f m")
                        toggle("Dynamic Island", "capsule.fill", \.fakeIsland)
                        toggle("Watermark", "textformat", \.watermark)
                        watermarkField
                    }
                    section("Lọc & hiệu năng") {
                        slider("Tầm xa tối đa", "arrow.up.and.down.and.arrow.left.and.right", \.maxDistance, 5...30, "%.0f m")
                        slider("Số người tối đa", "person.2.fill", \.maxPeople, 5...20, "%.0f")
                        toggle("Chế độ mượt (60 Hz)", "bolt.fill", \.smoothMode)
                    }
                    section("Quay video") {
                        toggle("Nút quay trên màn hình", "record.circle", \.recordButton)
                        toggle("Chấm đỏ khi đang quay", "smallcircle.filled.circle", \.recordIndicator)
                        toggle("Thu mic", "mic.fill", \.microphone)
                        toggle("Rung", "iphone.radiowaves.left.and.right", \.haptics)
                    }
                    section("Màu chủ đạo") { accentRow }
                    aboutSection
                }
                .padding(16)
            }
            .scrollIndicators(.hidden)
        }
        .tint(accent)
        .glassEffect(.regular, in: .rect(cornerRadius: 28))
        .sensoryFeedback(.selection, trigger: feedbackKey) { _, _ in store.settings.haptics }
    }

    /// Settings minus free text, so typing the watermark doesn't buzz on every key.
    private var feedbackKey: Settings {
        var s = store.settings
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
                Text("ESP Menu").font(.headline)
                Text("v2.6 · Undetected ✓").font(.caption).foregroundStyle(.secondary)
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

    private var presetSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionTitle("Preset")
                Spacer()
                if store.settings.preset == .custom {
                    Text("Custom").font(.caption.weight(.semibold)).foregroundStyle(accent)
                }
            }
            Picker("Preset", selection: Binding(get: { store.settings.preset },
                                                set: { store.apply($0) })) {
                Text("LEGIT").tag(Preset.legit)
                Text("VIP").tag(Preset.vip)
                Text("STREAMER").tag(Preset.streamer)
                Text("OFF").tag(Preset.off)
            }
            .pickerStyle(.segmented)
        }
    }

    private var watermarkField: some View {
        HStack(spacing: 12) {
            rowIcon("character.cursor.ibeam")
            TextField("Chữ watermark", text: store.binding(\.watermarkText))
                .textFieldStyle(.plain)
                .submitLabel(.done)
        }
        .padding(.vertical, 10)
    }

    private var accentRow: some View {
        HStack(spacing: 10) {
            ForEach(AccentName.allCases, id: \.self) { name in
                Button {
                    store.settings.set(\.accent, name)
                } label: {
                    Circle()
                        .fill(Palette.accent(name))
                        .frame(width: 26, height: 26)
                        .overlay {
                            if store.settings.accent == name {
                                Circle().strokeBorder(.white, lineWidth: 2.5).padding(-4)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 12)
    }

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("Về app")
            Text("v2.6 · Undetected ✓").font(.subheadline.weight(.semibold))
            if modelWarning {
                Label("Không tải được model YOLO — đang dùng nhận diện dự phòng, kém hơn và không có con vật/đồ vật.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(Palette.partial)
            }
            Text("Chạm 2 lần bằng 3 ngón để mở/đóng menu. Giữ 3 ngón để quay video. Nếu bật Trợ năng → Thu phóng, iOS sẽ chiếm cử chỉ chạm 3 ngón.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Rows

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle(title)
            VStack(spacing: 0) { content() }
                .padding(.horizontal, 14)
                .background(Color.white.opacity(0.07), in: .rect(cornerRadius: 16))
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.leading, 4)
    }

    private func rowIcon(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(accent)
            .frame(width: 22)
    }

    private func toggle(_ title: String, _ symbol: String, _ keyPath: WritableKeyPath<Settings, Bool>) -> some View {
        Toggle(isOn: store.binding(keyPath)) {
            HStack(spacing: 12) {
                rowIcon(symbol)
                Text(title).font(.subheadline)
            }
        }
        .padding(.vertical, 7)
    }

    private func picker<V: Hashable>(_ title: String, _ symbol: String, _ keyPath: WritableKeyPath<Settings, V>,
                                     _ options: [(V, String)]) -> some View {
        HStack(spacing: 12) {
            rowIcon(symbol)
            Text(title).font(.subheadline)
            Spacer()
            Picker(title, selection: store.binding(keyPath)) {
                ForEach(options, id: \.0) { option in
                    Text(option.1).tag(option.0)
                }
            }
            .pickerStyle(.menu)
        }
        .padding(.vertical, 4)
    }

    private func slider(_ title: String, _ symbol: String, _ keyPath: WritableKeyPath<Settings, Double>,
                        _ range: ClosedRange<Double>, _ format: String) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 12) {
                rowIcon(symbol)
                Text(title).font(.subheadline)
                Spacer()
                Text(String(format: format, store.settings[keyPath: keyPath]))
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: store.binding(keyPath), in: range)
        }
        .padding(.vertical, 8)
    }
}
