import XCTest
@testable import PhotoCleanerCore

final class IncrementalDeletionTests: XCTestCase {
    func testPruningPreservesRemainingGroupAndItsSuggestedSurvivor() {
        let group = DuplicateGroup(id: "group", memberIDs: ["a", "b", "c"], suggestedKeepID: "b")
        XCTAssertEqual(group.removing(ids: ["elsewhere"]), group)
        let remaining = group.removing(ids: ["a"])
        XCTAssertEqual(remaining?.id, group.id)
        XCTAssertEqual(remaining?.memberIDs, ["b", "c"])
        XCTAssertEqual(remaining?.suggestedKeepID, "b")
        XCTAssertEqual(group.removing(ids: ["b"])?.suggestedKeepID, "a")
        XCTAssertNil(group.removing(ids: ["a", "b"]))
        XCTAssertNil(group.removing(ids: ["a", "b", "c"]))
    }

    func testPruningManyGroupsOnlyChangesGroupsContainingDeletedIDs() {
        let groups = (0..<4000).map { index in
            DuplicateGroup(id: "g\(index)", memberIDs: ["\(index)-a", "\(index)-b"], suggestedKeepID: "\(index)-b")
        }
        let remaining = groups.compactMap { $0.removing(ids: ["10-a", "3900-b"]) }
        XCTAssertEqual(remaining.count, groups.count - 2)
        XCTAssertEqual(remaining, groups.filter { $0.id != "g10" && $0.id != "g3900" })
    }
}
