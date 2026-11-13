import Foundation
import XCTest
import PhotoCleanerCore

final class LocalIndexTests: XCTestCase {
    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    func testFeaturesStayOnDiskAcrossReloadAndAreRemovedWithDeletedRecords() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let index = LocalIndex(directory: directory)
        let feature = Data(repeating: 7, count: 64 * 1024)
        let record = MediaRecord(id: "photo/id", featurePrint: feature, text: "测试文字", analysisState: .complete)
        try await index.upsert([record])
        let reopened = LocalIndex(directory: directory)
        let loaded = try await reopened.load()
        XCTAssertNil(loaded[record.id]?.featurePrint)
        XCTAssertEqual(loaded[record.id]?.text, record.text)
        let stored = await reopened.featurePrint(id: record.id)
        XCTAssertEqual(stored, feature)
        try await reopened.retain(ids: [])
        let removed = await reopened.featurePrint(id: record.id)
        XCTAssertNil(removed)
        let empty = try await reopened.load()
        XCTAssertTrue(empty.isEmpty)
    }

    func testLegacyEmbeddedFeaturesMigrateWithoutLosingSearchOrAnalysis() async throws {
        struct LegacyPage: Encodable {
            let version = 1
            let records: [String: MediaRecord]
        }
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let record = MediaRecord(id: "old", digest: "original", featurePrint: Data([1, 2, 3]),
            customTags: ["工作"], text: "旧文字", analysisState: .complete)
        try JSONEncoder().encode(LegacyPage(records: [record.id: record]))
            .write(to: directory.appendingPathComponent("1.json"))
        let index = LocalIndex(directory: directory)
        let loaded = try await index.load()
        XCTAssertNil(loaded[record.id]?.featurePrint)
        XCTAssertEqual(loaded[record.id]?.digest, record.digest)
        XCTAssertEqual(loaded[record.id]?.text, record.text)
        let feature = await index.featurePrint(id: record.id)
        XCTAssertEqual(feature, record.featurePrint)
        let reloaded = try await LocalIndex(directory: directory).load()
        XCTAssertEqual(reloaded, loaded)
    }

    func testClearingIndexRemovesFeaturesAndAllowsRescanWrites() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let index = LocalIndex(directory: directory)
        try await index.upsert([MediaRecord(id: "old", featurePrint: Data([1]))])
        try await index.clear()
        let missing = await index.featurePrint(id: "old")
        XCTAssertNil(missing)
        try await index.upsert([MediaRecord(id: "new", text: "新文字")])
        let records = try await index.load()
        XCTAssertEqual(Set(records.keys), ["new"])
    }
}
