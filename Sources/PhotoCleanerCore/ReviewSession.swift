import Foundation

public enum ReviewDecision: String, CaseIterable, Sendable { case delete, keep, favorite, skip }

public struct ReviewStep: Sendable {
    public let id: String
    public let decision: ReviewDecision
    public let wasSelected: Bool
    public let wasFavoritePending: Bool
}

public struct ReviewSession: Sendable {
    public let ids: [String]
    private var history: [ReviewStep] = []

    public init(ids: [String]) { self.ids = ids }
    public var completedCount: Int { history.count }
    public var currentID: String? { history.count < ids.count ? ids[history.count] : nil }
    public var canUndo: Bool { !history.isEmpty }

    public mutating func decide(_ decision: ReviewDecision, wasSelected: Bool, wasFavoritePending: Bool = false) {
        guard let id = currentID else { return }
        history.append(ReviewStep(id: id, decision: decision, wasSelected: wasSelected, wasFavoritePending: wasFavoritePending))
    }

    @discardableResult
    public mutating func undo() -> ReviewStep? { history.popLast() }
}

public enum ReviewScope: String, CaseIterable, Sendable {
    case all, photos, videos, screenshots, livePhotos, favorites

    public func matches(_ record: MediaRecord) -> Bool {
        switch self {
        case .all: return true
        case .photos: return record.kind == .image
        case .videos: return record.kind == .video
        case .screenshots: return record.isScreenshot
        case .livePhotos: return record.isLivePhoto
        case .favorites: return record.isFavorite
        }
    }
}

public struct ReviewMonth: Identifiable, Sendable {
    public var id: String { date.map { String($0.timeIntervalSince1970) } ?? "undated" }
    public let date: Date?
    public let ids: [String]

    public static func group(_ records: [MediaRecord], calendar: Calendar = .current) -> [ReviewMonth] {
        var dated: [Date: [String]] = [:]
        var undated: [String] = []
        for record in MediaSorter.sorted(records, by: .newest) {
            if let created = record.createdAt, let start = calendar.dateInterval(of: .month, for: created)?.start {
                dated[start, default: []].append(record.id)
            } else { undated.append(record.id) }
        }
        var months = dated.keys.sorted(by: >).map { ReviewMonth(date: $0, ids: dated[$0]!) }
        if !undated.isEmpty { months.append(ReviewMonth(date: nil, ids: undated)) }
        return months
    }
}
