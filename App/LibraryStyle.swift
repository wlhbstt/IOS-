import SwiftUI
import PhotoCleanerCore

enum LibraryStyle {
    static let accent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.30, green: 0.82, blue: 0.68, alpha: 1)
            : UIColor(red: 0.06, green: 0.42, blue: 0.34, alpha: 1)
    })
}

struct CleanupDestination: View {
    let title: String
    let value: String
    let symbol: String
    let color: Color
    let ids: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: symbol).foregroundStyle(color)
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                Spacer(minLength: 0)
            }
            HStack(spacing: 3) {
                if ids.isEmpty {
                    ZStack {
                        color.opacity(0.08)
                        Image(systemName: symbol).font(.title2).foregroundStyle(color.opacity(0.65))
                    }
                } else {
                    ForEach(Array(ids.prefix(2)), id: \.self) { id in PhotoThumbnail(id: id) }
                }
            }
            .frame(height: 76).clipped().clipShape(RoundedRectangle(cornerRadius: 4))
            HStack {
                Text(value).font(.headline.monospacedDigit()).foregroundStyle(.primary)
                Spacer()
                Image(systemName: "arrow.up.right").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
        .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(Color(uiColor: .separator).opacity(0.22)) }
        .contentShape(Rectangle())
    }
}

struct LibraryMetric: View {
    let title: String
    let value: Int
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value.formatted()).font(.title3.weight(.semibold).monospacedDigit()).foregroundStyle(color)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title).accessibilityValue("\(value)")
            .accessibilityIdentifier("library.metric.\(title)")
    }
}
