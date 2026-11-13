import XCTest

final class ReviewUITests: XCTestCase {
    @MainActor
    func testSwipeUndoFavoritesReviewAndDeletion() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["整理"].waitForExistence(timeout: 20))
        app.tabBars.buttons["整理"].tap()
        let count = app.staticTexts["organize.count"]
        XCTAssertTrue(count.waitForExistence(timeout: 15))
        let originalCount = Int(count.value as? String ?? count.label)
        XCTAssertNotNil(originalCount)
        capture("08-organize")
        app.buttons["review.start"].tap()
        let image = app.images["review.image"].firstMatch
        let loaded = image.waitForExistence(timeout: 30)
        if !loaded { capture("09-review-load-failure"); print(app.debugDescription) }
        XCTAssertTrue(loaded)
        let progress = app.staticTexts["review.progress"]
        let pending = app.buttons["review.pending"]
        capture("09-swipe-photo")

        image.swipeLeft()
        expect(progress, label: "1 /")
        XCTAssertTrue(pending.label.contains("1"))
        capture("10-swipe-delete-staged")
        app.buttons["review.undo"].tap()
        expect(progress, label: "0 /")
        XCTAssertFalse(pending.isEnabled)
        XCTAssertTrue(image.waitForExistence(timeout: 20))
        image.swipeRight()
        expect(progress, label: "1 /")
        XCTAssertFalse(pending.isEnabled)
        app.buttons["review.undo"].tap()
        XCTAssertTrue(image.waitForExistence(timeout: 20))
        image.swipeUp()
        expect(progress, label: "1 /")
        XCTAssertTrue(pending.label.contains("1"))
        app.buttons["review.undo"].tap()
        XCTAssertTrue(image.waitForExistence(timeout: 20))
        image.swipeDown()
        expect(progress, label: "1 /")
        XCTAssertFalse(pending.isEnabled)
        app.buttons["review.undo"].tap()
        app.buttons["review.favorite"].tap()
        pending.tap()
        XCTAssertTrue(app.buttons["pending.favorite"].waitForExistence(timeout: 10))
        capture("11-favorite-review")
        app.buttons["pending.favorite"].tap()
        expectation(for: NSPredicate(format: "label CONTAINS '0' AND enabled == false"), evaluatedWith: app.buttons["pending.favorite"])
        waitForExpectations(timeout: 30)
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: app.buttons["pending.close"])
        waitForExpectations(timeout: 20)
        app.buttons["pending.close"].tap()

        let delete = app.buttons["review.delete"]
        if app.staticTexts["review.filename"].label.localizedCaseInsensitiveContains("compression-fixture") {
            app.buttons["review.keep"].tap()
        }
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: delete)
        waitForExpectations(timeout: 20)
        delete.tap()
        pending.tap()
        let commit = app.buttons["pending.delete"]
        XCTAssertTrue(commit.waitForExistence(timeout: 10))
        capture("12-delete-review")
        commit.tap()
        let dialog = systemDialog(app)
        XCTAssertTrue(dialog.waitForExistence(timeout: 10))
        let cancel = dialog.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] 'Cancel' OR label BEGINSWITH '取消' OR label MATCHES[c] 'Don.t Allow' OR label == '不允许'")).firstMatch
        XCTAssertTrue(cancel.exists)
        cancel.tap()
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: commit)
        waitForExpectations(timeout: 20)
        commit.tap()
        let confirmed = systemDialog(app)
        XCTAssertTrue(confirmed.waitForExistence(timeout: 10))
        confirmed.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] 'Delete' OR label BEGINSWITH '删除'")).firstMatch.tap()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: commit)
        waitForExpectations(timeout: 30)
        XCTAssertFalse(pending.isEnabled)
        capture("13-review-after-delete")
        app.navigationBars.buttons["完成"].tap()
        expectation(for: NSPredicate { _, _ in
            Int(count.value as? String ?? count.label) == (originalCount ?? 0) - 1
        }, evaluatedWith: count)
        waitForExpectations(timeout: 20)
    }

    @MainActor
    func testCollectionsDoubleRowsAndCompressionCopy() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["整理"].waitForExistence(timeout: 20))
        app.tabBars.buttons["整理"].tap()
        let count = app.staticTexts["organize.count"]
        XCTAssertTrue(count.waitForExistence(timeout: 15))
        let before = Int(count.value as? String ?? count.label)
        app.buttons["organize.scope.photos"].tap()
        XCTAssertTrue(app.buttons["browser.layout"].waitForExistence(timeout: 10))
        app.buttons["browser.layout"].tap()
        XCTAssertTrue(app.scrollViews["browser.twoRows"].waitForExistence(timeout: 5))
        capture("14-two-row-browser")
        app.buttons["browser.layout"].tap()
        app.navigationBars.buttons["整理"].tap()
        app.buttons["organize.scope.favorites"].tap()
        XCTAssertTrue(app.navigationBars["收藏"].waitForExistence(timeout: 10))
        capture("15-favorites")
        app.tabBars.buttons["清理"].tap()
        app.swipeUp()
        XCTAssertTrue(app.buttons["library.compression"].waitForExistence(timeout: 10))
        app.buttons["library.compression"].tap()
        let fixture = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'compression.source.' AND identifier CONTAINS[c] 'compression-fixture'")).firstMatch
        for _ in 0..<6 {
            if fixture.exists && fixture.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(fixture.waitForExistence(timeout: 15))
        fixture.tap()
        let accept = app.switches["compression.acceptLoss"]
        XCTAssertTrue(accept.waitForExistence(timeout: 5))
        accept.coordinate(withNormalizedOffset: CGVector(dx: 0.90, dy: 0.5)).tap()
        expectation(for: NSPredicate(format: "value == '1'"), evaluatedWith: accept)
        waitForExpectations(timeout: 5)
        app.swipeUp()
        app.buttons["compression.prepare"].tap()
        XCTAssertTrue(app.staticTexts["压缩预览"].waitForExistence(timeout: 60))
        let save = app.buttons["compression.save"]
        for _ in 0..<6 {
            if save.exists && save.isHittable { break }
            app.swipeUp()
        }
        let ready = save.waitForExistence(timeout: 10) && save.isHittable
        if !ready { print(app.debugDescription) }
        XCTAssertTrue(ready)
        XCTAssertTrue(app.images["compression.previewImage"].waitForExistence(timeout: 15))
        capture("16-compression-preview")
        save.tap()
        XCTAssertTrue(app.staticTexts["原件已保留"].waitForExistence(timeout: 30))
        capture("17-compressed-copy-saved")
        app.tabBars.buttons["整理"].tap()
        app.navigationBars.buttons["整理"].tap()
        expectation(for: NSPredicate { _, _ in
            Int(count.value as? String ?? count.label) == (before ?? 0) + 1
        }, evaluatedWith: count)
        waitForExpectations(timeout: 20)
    }

    @MainActor
    private func expect(_ element: XCUIElement, label prefix: String) {
        expectation(for: NSPredicate(format: "label BEGINSWITH %@", prefix), evaluatedWith: element)
        waitForExpectations(timeout: 15)
    }

    @MainActor
    private func systemDialog(_ app: XCUIApplication) -> XCUIElement {
        let dialog = app.alerts.firstMatch
        return dialog.waitForExistence(timeout: 3) ? dialog : XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
    }

    @MainActor
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
