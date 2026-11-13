import Foundation

public struct DuplicateGroup: Identifiable, Hashable, Sendable {
    public var id: String
    public var memberIDs: [String]
    public var suggestedKeepID: String

    public init(id: String, memberIDs: [String], suggestedKeepID: String) {
        self.id = id
        self.memberIDs = memberIDs
        self.suggestedKeepID = suggestedKeepID
    }
}

public enum DuplicateFinder {
    public static func exactGroups(_ records: [MediaRecord]) -> [DuplicateGroup] {
        let eligible = records.filter {
            $0.kind == .image && !$0.isComplex && !$0.isLivePhoto && !($0.digest ?? "").isEmpty
        }
        let byDigest = Dictionary(grouping: eligible, by: { $0.digest! })
        return byDigest.keys.sorted().compactMap { digest in
            guard let members = byDigest[digest], members.count > 1 else { return nil }
            let ranked = members.sorted(by: preferKeeping)
            return DuplicateGroup(id: "exact:\(digest)", memberIDs: members.map(\.id).sorted(), suggestedKeepID: ranked[0].id)
        }
    }

    private static func preferKeeping(_ left: MediaRecord, _ right: MediaRecord) -> Bool {
        if left.isFavorite != right.isFavorite { return left.isFavorite }
        let leftPixels = Double(left.width) * Double(left.height)
        let rightPixels = Double(right.width) * Double(right.height)
        if leftPixels != rightPixels { return leftPixels > rightPixels }
        if left.createdAt != right.createdAt {
            guard let a = left.createdAt else { return false }
            guard let b = right.createdAt else { return true }
            return a < b
        }
        return left.id < right.id
    }
}

public enum DeletionPolicyError: Error, Equatable, LocalizedError {
    case emptySelection
    case missingRecords
    case favoriteOrProtected
    case wouldRemoveEntireGroup
    case changedSinceReview

    public var errorDescription: String? {
        switch self {
        case .emptySelection: return "请先选择要删除的照片。"
        case .missingRecords: return "部分照片已变化，请刷新后重新选择。"
        case .favoriteOrProtected: return "选择中包含收藏或已保护的照片。"
        case .wouldRemoveEntireGroup: return "每组至少需要保留一张当前仍存在的照片。"
        case .changedSinceReview: return "照片或同组保留项已变化，请刷新后重新确认。"
        }
    }
}

public enum DeletionPolicy {
    public static func validateCompressedOriginal(originalID: String, modifiedAt: Date?, copyID: String, currentRecords: [MediaRecord]) throws {
        guard originalID != copyID, currentRecords.contains(where: { $0.id == copyID }),
              currentRecords.contains(where: { $0.id == originalID && $0.modifiedAt == modifiedAt }) else {
            throw DeletionPolicyError.changedSinceReview
        }
    }

    public static func validateUnchanged(selectedIDs: Set<String>, reviewedRecords: [MediaRecord], currentRecords: [MediaRecord], groups: [DuplicateGroup]) throws {
        var relevantIDs = selectedIDs
        for group in groups where group.memberIDs.contains(where: selectedIDs.contains) {
            relevantIDs.formUnion(group.memberIDs)
        }
        let reviewedByID = Dictionary(reviewedRecords.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        let currentByID = Dictionary(currentRecords.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        for id in relevantIDs {
            guard let reviewed = reviewedByID[id], let current = currentByID[id],
                  reviewed.modifiedAt == current.modifiedAt,
                  reviewed.createdAt == current.createdAt,
                  reviewed.filename == current.filename,
                  reviewed.width == current.width,
                  reviewed.height == current.height,
                  reviewed.kind == current.kind,
                  reviewed.isComplex == current.isComplex,
                  reviewed.isLivePhoto == current.isLivePhoto,
                  reviewed.digest == nil || reviewed.digest == current.digest else {
                throw DeletionPolicyError.changedSinceReview
            }
        }
    }

    public static func validate(selectedIDs: Set<String>, records: [MediaRecord], protectedIDs: Set<String>, groups: [DuplicateGroup]) throws {
        guard !selectedIDs.isEmpty else { throw DeletionPolicyError.emptySelection }
        let existingIDs = Set(records.map(\.id))
        guard selectedIDs.isSubset(of: existingIDs) else { throw DeletionPolicyError.missingRecords }
        let favorites = Set(records.filter(\.isFavorite).map(\.id))
        guard selectedIDs.isDisjoint(with: protectedIDs.union(favorites)) else { throw DeletionPolicyError.favoriteOrProtected }
        for group in groups {
            let existingMembers = Set(group.memberIDs).intersection(existingIDs)
            if !existingMembers.isEmpty && existingMembers.isSubset(of: selectedIDs) {
                throw DeletionPolicyError.wouldRemoveEntireGroup
            }
        }
    }
}
