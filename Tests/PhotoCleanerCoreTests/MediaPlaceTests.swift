import Foundation
import XCTest
@testable import PhotoCleanerCore

final class MediaPlaceTests: XCTestCase {
    func testOldJSONWithoutLocationDecodesAndNewLocationRoundTrips() throws {
        let original = MediaRecord(id: "old", customTags: ["保留"])
        let encoded = try JSONEncoder().encode(original)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        json.removeValue(forKey: "latitude")
        json.removeValue(forKey: "longitude")
        let decoded = try JSONDecoder().decode(MediaRecord.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(decoded.latitude)
        XCTAssertNil(decoded.longitude)
        XCTAssertEqual(decoded.customTags, ["保留"])
        let located = MediaRecord(id: "located", latitude: -33.86, longitude: 151.21)
        XCTAssertEqual(try JSONDecoder().decode(MediaRecord.self, from: JSONEncoder().encode(located)), located)
    }

    func testMetadataRefreshUpdatesLocationWithoutDiscardingAnalysis() {
        let analyzed = MediaRecord(id: "photo", latitude: 12, longitude: 23,
            digest: "digest", tags: ["风景"], customTags: ["旅行"], analysisState: .complete)
        let moved = analyzed.updatingMetadata(from: MediaRecord(id: "photo", latitude: -33.86, longitude: 151.21))
        XCTAssertEqual(moved.latitude, -33.86)
        XCTAssertEqual(moved.longitude, 151.21)
        XCTAssertEqual(moved.digest, "digest")
        XCTAssertEqual(moved.tags, ["风景"])
        XCTAssertEqual(moved.analysisState, .complete)
        let removed = moved.updatingMetadata(from: MediaRecord(id: "photo"))
        XCTAssertNil(removed.latitude)
        XCTAssertNil(removed.longitude)
        let changed = moved.updatingMetadata(from: MediaRecord(id: "photo", filename: "changed", latitude: 1, longitude: 2))
        XCTAssertEqual(changed.latitude, 1)
        XCTAssertEqual(changed.longitude, 2)
        XCTAssertEqual(changed.customTags, ["旅行"])
    }

    func testGroupingUsesNegativeGridCellsAndStableNewestOrder() {
        let records = [
            MediaRecord(id: "b", latitude: -0.01, longitude: -0.01),
            MediaRecord(id: "a", latitude: -0.09, longitude: -0.09),
            MediaRecord(id: "recent", createdAt: Date(timeIntervalSince1970: 100), latitude: -0.05, longitude: -0.05),
            MediaRecord(id: "positive", latitude: 0.01, longitude: 0.01)
        ]
        let groups = MediaPlace.group(records)
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups.first?.id, "-1:-1")
        XCTAssertEqual(groups.first?.latitude, -0.05)
        XCTAssertEqual(groups.first?.longitude, -0.05)
        XCTAssertEqual(groups.first?.ids, ["recent", "a", "b"])
        XCTAssertEqual(MediaPlace.group(Array(records.reversed())), groups)
    }

    func testInvalidAndPartialCoordinatesAreExcludedAndBoundariesAreValid() {
        let records = [
            MediaRecord(id: "none"), MediaRecord(id: "partial", latitude: 1),
            MediaRecord(id: "nan", latitude: .nan, longitude: 1),
            MediaRecord(id: "infinite", latitude: 1, longitude: .infinity),
            MediaRecord(id: "south", latitude: -90.01, longitude: 0),
            MediaRecord(id: "east", latitude: 0, longitude: 180.01),
            MediaRecord(id: "northEast", latitude: 90, longitude: 180),
            MediaRecord(id: "southWest", latitude: -90, longitude: -180)
        ]
        let groups = MediaPlace.group(records)
        XCTAssertEqual(Set(groups.flatMap(\.ids)), ["northEast", "southWest"])
        XCTAssertTrue(groups.allSatisfy { (-90...90).contains($0.latitude) && (-180...180).contains($0.longitude) })
        XCTAssertEqual(Set(groups.map(\.id)), ["899:1799", "-900:-1800"])
    }
}
