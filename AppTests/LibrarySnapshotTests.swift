import Foundation
import XCTest
import PhotoCleanerCore

final class LibrarySnapshotTests: XCTestCase {
    func testSummaryPreservesRecordsAndCountsWithoutCopyingFeatureDataIntoUI() {
        let source = [
            MediaRecord(id: "screenshot", isScreenshot: true, originalBytes: 42, featurePrint: Data([1, 2]),
                tags: ["截图", "文档"], customTags: ["文档"], text: "搜索文字", analysisState: .complete),
            MediaRecord(id: "photo", tags: ["疑似模糊", "疑似极暗", "文档"])
        ]
        let summary = LibrarySnapshot(source)
        XCTAssertEqual(summary.records.map(\.id), source.map(\.id))
        XCTAssertEqual(summary.records.first?.text, "搜索文字")
        XCTAssertNil(summary.records.first?.featurePrint)
        XCTAssertEqual(source.first?.featurePrint, Data([1, 2]))
        XCTAssertEqual(summary.analyzed, 1)
        XCTAssertEqual(summary.unknownSize, 1)
        XCTAssertEqual(summary.screenshots, ["screenshot"])
        XCTAssertEqual(summary.quality, ["photo"])
        XCTAssertEqual(summary.categories.first?.name, "文档")
        XCTAssertEqual(summary.categories.first?.count, 2)
        XCTAssertEqual(summary.previews["文档"], "screenshot")
    }
}
