import Foundation
import XCTest
@testable import PhotoCleanerCore

final class ReviewSessionTests: XCTestCase {
    func testPreviousGestureReturnsWithoutAddingAnotherDecision() {
        let previous = ReviewDecision(rawValue: "previous")
        XCTAssertNotNil(previous, "手势设置必须支持上一张")
        guard let previous else { return }
        var session = ReviewSession(ids: ["a", "b"])
        session.decide(previous, wasSelected: false)
        XCTAssertEqual(session.currentID, "a")
        session.decide(.delete, wasSelected: false)
        session.decide(previous, wasSelected: false)
        XCTAssertEqual(session.currentID, "a")
        XCTAssertEqual(session.completedCount, 0)
        XCTAssertNil(session.undo())
        session.decide(.keep, wasSelected: false)
        session.decide(.skip, wasSelected: false)
        session.decide(previous, wasSelected: false)
        XCTAssertEqual(session.currentID, "b")
        XCTAssertEqual(session.completedCount, 1)
    }

    func testDecisionsAdvanceAndUndoRestoresPreviousSelectionState() {
        var session = ReviewSession(ids: ["a", "b", "c"])
        XCTAssertEqual(session.currentID, "a")
        session.decide(.delete, wasSelected: false)
        session.decide(.keep, wasSelected: true)
        XCTAssertEqual(session.currentID, "c")
        XCTAssertEqual(session.completedCount, 2)
        let undone = session.undo()
        XCTAssertEqual(undone?.id, "b")
        XCTAssertEqual(undone?.decision, .keep)
        XCTAssertEqual(undone?.wasSelected, true)
        XCTAssertEqual(session.currentID, "b")
        XCTAssertEqual(session.undo()?.wasSelected, false)
        XCTAssertEqual(session.currentID, "a")
        XCTAssertNil(session.undo())
    }

    func testRemovingConfirmedDeletionsKeepsCurrentPhotoAndValidHistory() {
        var session = ReviewSession(ids: ["deleted", "kept", "current", "future"])
        session.decide(.delete, wasSelected: false)
        session.decide(.keep, wasSelected: false)
        session.retain(ids: ["kept", "current"])
        XCTAssertEqual(session.ids, ["kept", "current"])
        XCTAssertEqual(session.currentID, "current")
        XCTAssertEqual(session.completedCount, 1)
        XCTAssertEqual(session.undo()?.id, "kept")
        XCTAssertEqual(session.currentID, "kept")
        XCTAssertNil(session.undo())
        session.retain(ids: [])
        XCTAssertNil(session.currentID)
        XCTAssertFalse(session.canUndo)
    }

    func testSkipAndCompletionDoNotOverflowAndCanUndoLastItem() {
        var session = ReviewSession(ids: ["a"])
        session.decide(.skip, wasSelected: true)
        XCTAssertNil(session.currentID)
        XCTAssertEqual(session.completedCount, 1)
        session.decide(.delete, wasSelected: false)
        XCTAssertEqual(session.completedCount, 1)
        XCTAssertEqual(session.undo()?.decision, .skip)
        XCTAssertEqual(session.currentID, "a")
        var empty = ReviewSession(ids: [])
        empty.decide(.keep, wasSelected: false)
        XCTAssertNil(empty.currentID)
        XCTAssertNil(empty.undo())
    }

    func testUndoFavoriteRestoresBothPendingActions() {
        var session = ReviewSession(ids: ["a"])
        session.decide(.favorite, wasSelected: true, wasFavoritePending: false)
        let step = session.undo()
        XCTAssertEqual(step?.decision, .favorite)
        XCTAssertEqual(step?.wasSelected, true)
        XCTAssertEqual(step?.wasFavoritePending, false)
        session.decide(.delete, wasSelected: false, wasFavoritePending: true)
        XCTAssertEqual(session.undo()?.wasFavoritePending, true)
    }

    func testMonthsUseCalendarBoundariesAndKeepUndatedLast() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        let formatter = ISO8601DateFormatter()
        let records = [
            MediaRecord(id: "unknown"),
            MediaRecord(id: "june", createdAt: formatter.date(from: "2026-06-01T00:00:00Z")),
            MediaRecord(id: "july", createdAt: formatter.date(from: "2026-06-30T16:00:00Z")),
            MediaRecord(id: "june-last", createdAt: formatter.date(from: "2026-06-30T15:59:59Z"))
        ]
        let months = ReviewMonth.group(records, calendar: calendar)
        XCTAssertEqual(months.count, 3)
        XCTAssertEqual(months[0].ids, ["july"])
        XCTAssertEqual(months[1].ids, ["june-last", "june"])
        XCTAssertEqual(months[2].ids, ["unknown"])
        XCTAssertNil(months[2].date)
        XCTAssertNotEqual(months[0].id, months[1].id)
    }

    func testMediaScopesWorkBeforeAnalysisAndDoNotConfuseVideosWithPhotos() {
        let photo = MediaRecord(id: "p")
        let video = MediaRecord(id: "v", kind: .video)
        let screenshot = MediaRecord(id: "s", isScreenshot: true)
        let live = MediaRecord(id: "l", isLivePhoto: true)
        let records = [photo, video, screenshot, live]
        XCTAssertEqual(records.filter(ReviewScope.all.matches).count, 4)
        XCTAssertEqual(records.filter(ReviewScope.photos.matches).map(\.id), ["p", "s", "l"])
        XCTAssertEqual(records.filter(ReviewScope.videos.matches).map(\.id), ["v"])
        XCTAssertEqual(records.filter(ReviewScope.screenshots.matches).map(\.id), ["s"])
        XCTAssertEqual(records.filter(ReviewScope.livePhotos.matches).map(\.id), ["l"])
        XCTAssertFalse(ReviewScope.favorites.matches(photo))
        XCTAssertTrue(ReviewScope.favorites.matches(MediaRecord(id: "f", isFavorite: true)))
    }
}
