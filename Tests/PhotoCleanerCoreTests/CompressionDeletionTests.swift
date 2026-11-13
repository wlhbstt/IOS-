import Foundation
import XCTest
@testable import PhotoCleanerCore

final class CompressionDeletionTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 100)

    func testOriginalAndDifferentCopyMustStillExist() throws {
        let original = MediaRecord(id: "original", modifiedAt: date)
        let copy = MediaRecord(id: "copy")
        XCTAssertNoThrow(try DeletionPolicy.validateCompressedOriginal(originalID: original.id, modifiedAt: date,
            copyID: copy.id, currentRecords: [original, copy]))
        for records in [[original], [copy], []] {
            XCTAssertThrowsError(try DeletionPolicy.validateCompressedOriginal(originalID: original.id, modifiedAt: date,
                copyID: copy.id, currentRecords: records))
        }
        XCTAssertThrowsError(try DeletionPolicy.validateCompressedOriginal(originalID: original.id, modifiedAt: date,
            copyID: original.id, currentRecords: [original]))
    }

    func testExternalEditsInvalidateOriginalDeletionEvenIfCopyExists() {
        let copy = MediaRecord(id: "copy")
        let changed = MediaRecord(id: "original", modifiedAt: date.addingTimeInterval(1))
        XCTAssertThrowsError(try DeletionPolicy.validateCompressedOriginal(originalID: changed.id, modifiedAt: date,
            copyID: copy.id, currentRecords: [changed, copy]))
        XCTAssertThrowsError(try DeletionPolicy.validateCompressedOriginal(originalID: changed.id, modifiedAt: nil,
            copyID: copy.id, currentRecords: [changed, copy]))
    }
}
