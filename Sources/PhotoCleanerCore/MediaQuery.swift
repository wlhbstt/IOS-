import Foundation

public enum MediaSort: String, CaseIterable, Codable, Hashable, Sendable {
    case sizeDescending, sizeAscending, newest, oldest
}

public enum MediaSorter {
    public static func sorted(_ records: [MediaRecord], by order: MediaSort) -> [MediaRecord] {
        records.sorted { left, right in
            switch order {
            case .sizeDescending, .sizeAscending:
                if left.originalBytes != right.originalBytes {
                    guard let a = left.originalBytes else { return false }
                    guard let b = right.originalBytes else { return true }
                    return order == .sizeDescending ? a > b : a < b
                }
            case .newest, .oldest:
                if left.createdAt != right.createdAt {
                    guard let a = left.createdAt else { return false }
                    guard let b = right.createdAt else { return true }
                    return order == .newest ? a > b : a < b
                }
            }
            return left.id < right.id
        }
    }
}

public struct MediaQuery: Sendable {
    public let text: String
    public let tag: String?
    public let startDate: Date?
    public let endDate: Date?
    private let terms: [[String]]

    public init(text: String = "", tag: String? = nil, startDate: Date? = nil, endDate: Date? = nil) {
        self.text = text
        self.tag = tag
        self.startDate = startDate
        self.endDate = endDate
        terms = text.split(whereSeparator: { $0.isWhitespace }).map {
            let term = Self.folded(String($0))
            return Self.aliases.first(where: { $0.contains(term) }) ?? [term]
        }
    }

    public func matches(_ record: MediaRecord) -> Bool {
        let calendar = Calendar.current
        if let startDate {
            guard let createdAt = record.createdAt, createdAt >= calendar.startOfDay(for: startDate) else { return false }
        }
        if let endDate {
            guard let createdAt = record.createdAt,
                  let nextDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: endDate)),
                  createdAt < nextDay else { return false }
        }
        let allTags = record.tags + record.customTags
        if let tag, !tag.isEmpty, !allTags.contains(where: { Self.folded($0) == Self.folded(tag) }) {
            return false
        }
        guard !terms.isEmpty else { return true }
        var searchable = [record.filename, record.text.filter { !$0.isWhitespace }] + allTags
        if let createdAt = record.createdAt {
            var gregorian = Calendar(identifier: .gregorian)
            gregorian.timeZone = calendar.timeZone
            let date = gregorian.dateComponents([.year, .month, .day], from: createdAt)
            if let year = date.year, let month = date.month, let day = date.day {
                searchable.append(String(format: "%04d-%02d-%02d", year, month, day))
                searchable.append("\(year)/\(month)/\(day)")
                searchable.append("\(year)年\(month)月\(day)日")
                searchable.append(String(format: "%04d/%02d/%02d", year, month, day))
                searchable.append(String(format: "%04d年%02d月%02d日", year, month, day))
                searchable.append("\(year)-\(month)-\(day)")
            }
        }
        let haystack = Self.folded(searchable.joined(separator: "\n"))
        return terms.allSatisfy { alternatives in alternatives.contains(where: haystack.contains) }
    }

    private static let aliases = [
        ["汽车", "车辆", "car"], ["人物", "人像", "自拍", "person"],
        ["风景", "景色", "landscape"], ["美食", "食物", "food"],
        ["截图", "截屏", "screenshot"], ["视频", "录像", "video"],
        ["文档", "文件", "document"], ["实况", "实况照片", "livephoto"]
    ]

    private static func folded(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
}
