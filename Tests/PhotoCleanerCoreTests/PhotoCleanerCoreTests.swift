import Foundation
import XCTest
@testable import PhotoCleanerCore

final class PhotoCleanerCoreTests: XCTestCase {
    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }

    func testSizeSortingUsesNumbersAndLeavesUnknownLastWithStableTies() {
        let records = [
            MediaRecord(id: "unknown"),
            MediaRecord(id: "b", originalBytes: 100),
            MediaRecord(id: "small", originalBytes: 9),
            MediaRecord(id: "a", originalBytes: 100)
        ]
        XCTAssertEqual(MediaSorter.sorted(records, by: .sizeDescending).map(\.id), ["a", "b", "small", "unknown"])
        XCTAssertEqual(MediaSorter.sorted(records, by: .sizeAscending).map(\.id), ["small", "a", "b", "unknown"])
    }

    func testDateSortingLeavesUndatedLastAndBreaksTiesByID() {
        let old = date("2024-01-01T12:00:00Z")
        let new = date("2025-01-01T12:00:00Z")
        let records = [MediaRecord(id: "none"), MediaRecord(id: "b", createdAt: old), MediaRecord(id: "a", createdAt: old), MediaRecord(id: "new", createdAt: new)]
        XCTAssertEqual(MediaSorter.sorted(records, by: .newest).map(\.id), ["new", "a", "b", "none"])
        XCTAssertEqual(MediaSorter.sorted(records, by: .oldest).map(\.id), ["a", "b", "new", "none"])
    }

    func testExactDuplicatesRequireOriginalDigestAndExcludeComplexResources() {
        let records = [
            MediaRecord(id: "original", digest: "same", perceptualHash: 1),
            MediaRecord(id: "copy", digest: "same", perceptualHash: 20),
            MediaRecord(id: "similar", digest: "different", perceptualHash: 1),
            MediaRecord(id: "unhashed", perceptualHash: 1),
            MediaRecord(id: "video", kind: .video, digest: "same"),
            MediaRecord(id: "edited", isComplex: true, digest: "same"),
            MediaRecord(id: "live", isLivePhoto: true, digest: "same")
        ]
        let groups = DuplicateFinder.exactGroups(records)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.memberIDs, ["copy", "original"])
    }

    func testDuplicateSurvivorPrefersFavoriteThenResolutionThenAgeThenID() {
        let old = date("2020-01-01T12:00:00Z")
        let new = date("2025-01-01T12:00:00Z")
        var records = [
            MediaRecord(id: "favorite", createdAt: new, isFavorite: true, width: 1, height: 1, digest: "same"),
            MediaRecord(id: "large", createdAt: old, width: 4000, height: 3000, digest: "same"),
            MediaRecord(id: "a", createdAt: old, width: 1000, height: 1000, digest: "same"),
            MediaRecord(id: "b", createdAt: old, width: 1000, height: 1000, digest: "same"),
            MediaRecord(id: "new", createdAt: new, width: 1000, height: 1000, digest: "same")
        ]
        XCTAssertEqual(DuplicateFinder.exactGroups(records).first?.suggestedKeepID, "favorite")
        records.removeAll { $0.id == "favorite" }
        XCTAssertEqual(DuplicateFinder.exactGroups(records).first?.suggestedKeepID, "large")
        records.removeAll { $0.id == "large" }
        XCTAssertEqual(DuplicateFinder.exactGroups(Array(records.reversed())).first?.suggestedKeepID, "a")
    }

    func testQueryCombinesTermsAcrossFieldsWithCaseAndDiacriticFolding() {
        let record = MediaRecord(id: "1", filename: "Cafe\u{301}.HEIC", createdAt: date("2024-06-12T12:00:00Z"), tags: ["Travel"], customTags: ["Family"], text: "TRAIN ticket")
        XCTAssertTrue(MediaQuery(text: "CAFÉ train family 2024").matches(record))
        XCTAssertTrue(MediaQuery(text: "2024-06-12", tag: "travel").matches(record))
        XCTAssertFalse(MediaQuery(text: "cafe missing").matches(record))
        XCTAssertFalse(MediaQuery(text: "train", tag: "work").matches(record))
        XCTAssertTrue(MediaQuery(text: " \n ").matches(record))
    }

    func testDateRangeIncludesTheWholeEndCalendarDay() {
        let calendar = Calendar.current
        let start = calendar.date(from: DateComponents(year: 2024, month: 6, day: 12))!
        let late = calendar.date(byAdding: .second, value: 86399, to: start)!
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: start)!
        let query = MediaQuery(startDate: start, endDate: start)
        XCTAssertTrue(query.matches(MediaRecord(id: "late", createdAt: late)))
        XCTAssertFalse(query.matches(MediaRecord(id: "next", createdAt: tomorrow)))
        XCTAssertFalse(query.matches(MediaRecord(id: "before", createdAt: start.addingTimeInterval(-1))))
        XCTAssertFalse(query.matches(MediaRecord(id: "unknown")))
    }

    func testWhitespaceQueryStillAppliesTagsAndCalendarDateFilters() {
        let calendar = Calendar.current
        let day = calendar.date(from: DateComponents(year: 2024, month: 6, day: 12))!
        let record = MediaRecord(id: "1", createdAt: day, customTags: ["Travel"])
        XCTAssertTrue(MediaQuery(text: " \t\n ").matches(MediaRecord(id: "undated")))
        XCTAssertTrue(MediaQuery(text: " \t\n ", tag: "travel", startDate: day, endDate: day).matches(record))
        XCTAssertFalse(MediaQuery(text: " \t\n ", tag: "work").matches(record))
        XCTAssertFalse(MediaQuery(text: " \t\n ", startDate: calendar.date(byAdding: .day, value: 1, to: day)).matches(record))
        XCTAssertFalse(MediaQuery(text: " \t\n ", endDate: day.addingTimeInterval(-1)).matches(record))
        XCTAssertFalse(MediaQuery(text: " \t\n ", startDate: day).matches(MediaRecord(id: "undated")))
    }

    func testDeletionRejectsEmptyMissingFavoriteAndProtectedSelections() {
        let records = [MediaRecord(id: "normal"), MediaRecord(id: "favorite", isFavorite: true), MediaRecord(id: "protected")]
        XCTAssertThrowsError(try DeletionPolicy.validate(selectedIDs: [], records: records, protectedIDs: [], groups: []))
        XCTAssertThrowsError(try DeletionPolicy.validate(selectedIDs: ["stale"], records: records, protectedIDs: [], groups: []))
        XCTAssertThrowsError(try DeletionPolicy.validate(selectedIDs: ["favorite"], records: records, protectedIDs: [], groups: []))
        XCTAssertThrowsError(try DeletionPolicy.validate(selectedIDs: ["protected"], records: records, protectedIDs: ["protected"], groups: []))
        XCTAssertNoThrow(try DeletionPolicy.validate(selectedIDs: ["normal"], records: records, protectedIDs: [], groups: []))
    }

    func testDeletionPreservesAtLeastOneMemberEvenInManuallySuppliedSimilarGroup() {
        let records = [MediaRecord(id: "a"), MediaRecord(id: "b")]
        let group = DuplicateGroup(id: "similar", memberIDs: ["a", "b"], suggestedKeepID: "a")
        XCTAssertThrowsError(try DeletionPolicy.validate(selectedIDs: ["a", "b"], records: records, protectedIDs: [], groups: [group]))
        XCTAssertNoThrow(try DeletionPolicy.validate(selectedIDs: ["b"], records: records, protectedIDs: [], groups: [group]))
        let staleGroup = DuplicateGroup(id: "stale", memberIDs: ["a", "removed"], suggestedKeepID: "removed")
        XCTAssertThrowsError(try DeletionPolicy.validate(selectedIDs: ["a"], records: records, protectedIDs: [], groups: [staleGroup]))
    }

    func testDeletionReviewRejectsSelectedResourceChanges() {
        let original = MediaRecord(id: "b", filename: "photo.heic", createdAt: date("2024-01-01T12:00:00Z"), modifiedAt: date("2024-01-01T12:00:00Z"), width: 100, height: 200, digest: "original")
        let changes: [(inout MediaRecord) -> Void] = [
            { $0.modifiedAt = $0.modifiedAt!.addingTimeInterval(1) },
            { $0.createdAt = $0.createdAt!.addingTimeInterval(1) },
            { $0.filename = "edited.heic" },
            { $0.width = 101 },
            { $0.height = 201 },
            { $0.kind = .video },
            { $0.isComplex = true },
            { $0.isLivePhoto = true },
            { $0.digest = "different" },
            { $0.digest = nil }
        ]
        for change in changes {
            var current = original
            change(&current)
            XCTAssertThrowsError(try DeletionPolicy.validateUnchanged(selectedIDs: ["b"], reviewedRecords: [original], currentRecords: [current], groups: [])) { error in
                XCTAssertEqual(error as? DeletionPolicyError, .changedSinceReview)
            }
        }
    }

    func testDeletionReviewRejectsEditedMissingOrUnreviewedGroupMembers() {
        let keeper = MediaRecord(id: "a", modifiedAt: date("2024-01-01T12:00:00Z"), digest: "original")
        let selected = MediaRecord(id: "b", digest: "original")
        let group = DuplicateGroup(id: "group", memberIDs: ["a", "b"], suggestedKeepID: "a")
        XCTAssertNoThrow(try DeletionPolicy.validateUnchanged(selectedIDs: ["b"], reviewedRecords: [keeper, selected], currentRecords: [keeper, selected], groups: [group]))
        var editedKeeper = keeper
        editedKeeper.modifiedAt = keeper.modifiedAt!.addingTimeInterval(1)
        for current in [[editedKeeper, selected], [selected], [keeper]] {
            XCTAssertThrowsError(try DeletionPolicy.validateUnchanged(selectedIDs: ["b"], reviewedRecords: [keeper, selected], currentRecords: current, groups: [group])) { error in
                XCTAssertEqual(error as? DeletionPolicyError, .changedSinceReview)
            }
        }
        XCTAssertThrowsError(try DeletionPolicy.validateUnchanged(selectedIDs: ["b"], reviewedRecords: [selected], currentRecords: [keeper, selected], groups: [group])) { error in
            XCTAssertEqual(error as? DeletionPolicyError, .changedSinceReview)
        }
        XCTAssertThrowsError(try DeletionPolicy.validateUnchanged(selectedIDs: ["b"], reviewedRecords: [], currentRecords: [selected], groups: [])) { error in
            XCTAssertEqual(error as? DeletionPolicyError, .changedSinceReview)
        }
        let extraMemberGroup = DuplicateGroup(id: "three-members", memberIDs: ["a", "b", "c"], suggestedKeepID: "a")
        let extraMember = MediaRecord(id: "c")
        XCTAssertThrowsError(try DeletionPolicy.validateUnchanged(selectedIDs: ["b"], reviewedRecords: [keeper, selected, extraMember], currentRecords: [keeper, selected], groups: [extraMemberGroup])) { error in
            XCTAssertEqual(error as? DeletionPolicyError, .changedSinceReview)
        }
    }

    func testDeletionReviewAllowsAnalysisUpdatesAndIgnoresUnrelatedGroups() {
        let reviewed = MediaRecord(id: "b")
        var analyzed = reviewed
        analyzed.originalBytes = 100
        analyzed.digest = "newly-computed"
        analyzed.text = "new OCR"
        analyzed.tags = ["文档"]
        analyzed.customTags = ["保留"]
        analyzed.perceptualHash = 123
        analyzed.featurePrint = Data([1])
        analyzed.brightness = 0.5
        analyzed.sharpness = 0.8
        analyzed.analysisState = .complete
        let unrelated = DuplicateGroup(id: "unrelated", memberIDs: ["missing-a", "missing-b"], suggestedKeepID: "missing-a")
        XCTAssertNoThrow(try DeletionPolicy.validateUnchanged(selectedIDs: ["b"], reviewedRecords: [reviewed], currentRecords: [analyzed], groups: [unrelated]))
    }

    func testScreenshotRulesRecognizeTemporaryTextConservatively() {
        XCTAssertEqual(ScreenshotRules.tags(for: "您的验证码 123456，五分钟内有效"), ["验证码"])
        XCTAssertEqual(ScreenshotRules.tags(for: "快递物流 运单号 123 正在派送"), ["物流"])
        XCTAssertEqual(ScreenshotRules.tags(for: "今天去公园散步"), [])
        XCTAssertFalse(ScreenshotRules.isSensitive(text: "您的验证码 123456"))
    }

    func testSensitiveDocumentsSuppressTemporaryScreenshotTags() {
        for text in ["发票 金额100元 验证码123456", "身份证号码 物流", "劳动合同 验证码", "Passport verification code 123456", "银行账号 快递取件码"] {
            XCTAssertTrue(ScreenshotRules.isSensitive(text: text), text)
            let tags = ScreenshotRules.tags(for: text)
            XCTAssertFalse(tags.contains("验证码"), text)
            XCTAssertFalse(tags.contains("物流"), text)
        }
        XCTAssertTrue(ScreenshotRules.tags(for: "电子发票 价税合计").contains("票据"))
        XCTAssertTrue(ScreenshotRules.tags(for: "劳动合同").contains("文档"))
    }

    func testMediaRecordRoundTripsOptionalAnalysisData() throws {
        let record = MediaRecord(id: "1", originalBytes: 9_000_000_000, digest: "abc", perceptualHash: UInt64.max, featurePrint: Data([1, 2, 3]), tags: ["票据"], customTags: ["保留"], text: "OCR", analysisState: .complete)
        XCTAssertEqual(try JSONDecoder().decode(MediaRecord.self, from: JSONEncoder().encode(record)), record)
    }

    func testResourceSizeRequiresEveryComponentAndAvoidsOverflow() {
        XCTAssertEqual(ResourceByteCounts.total([100, 200, 0]), 300)
        XCTAssertNil(ResourceByteCounts.total([]))
        XCTAssertNil(ResourceByteCounts.total([100, nil]))
        XCTAssertNil(ResourceByteCounts.total([100, -1]))
        XCTAssertNil(ResourceByteCounts.total([Int64.max, 1]))
    }
}
