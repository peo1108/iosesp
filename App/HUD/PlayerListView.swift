import ESPCore
import SwiftUI

/// "TRONG KHUNG": everyone in view, nearest first.
struct PlayerListView: View {
    struct Row: Identifiable {
        let id: Int
        let label: String
        let detail: String
        /// Already formatted ("2.3 m", "~8.1 m").
        let distance: String
        let color: Color
    }

    let rows: [Row]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("TRONG KHUNG")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
            if rows.isEmpty {
                Text("Không có ai").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(rows.prefix(8)) { row in
                HStack(spacing: 6) {
                    Circle().fill(row.color).frame(width: 6, height: 6)
                    Text(row.label).fontWeight(.semibold)
                    Text(row.detail).foregroundStyle(.secondary).lineLimit(1)
                    Spacer(minLength: 8)
                    Text(row.distance).monospacedDigit()
                }
                .font(.caption)
                .transition(.opacity)
            }
        }
        .frame(width: 210, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .animation(.easeInOut(duration: 0.25), value: rows.map(\.id))
    }
}
