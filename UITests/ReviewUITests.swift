import XCTest

final class ReviewUITests: XCTestCase {
    @MainActor
    func testPhotoEditorFiltersAndSaveCopy() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        waitForCatalogue(app)
        let count = app.staticTexts["organize.count"]
        let before = Int(count.value as? String ?? "")
        XCTAssertNotNil(before)
        app.buttons["review.start"].tap()
        let detail = app.buttons["照片详情"]
        XCTAssertTrue(detail.waitForExistence(timeout: 15))
        detail.tap()
        let edit = app.buttons["photo.editor.open"]
        XCTAssertTrue(edit.waitForExistence(timeout: 15))
        if !edit.isHittable { app.swipeUp() }
        edit.tap()
        XCTAssertTrue(app.images["photo.editor.preview"].waitForExistence(timeout: 20))
        app.buttons["滤镜"].tap()
        let warm = app.buttons["photo.editor.filter.warm"]
        XCTAssertTrue(warm.waitForExistence(timeout: 10))
        expectation(for: NSPredicate(format: "value == %@", "预览已生成"), evaluatedWith: warm)
        waitForExpectations(timeout: 15)
        warm.tap()
        capture("21-photo-editor-filters")
        app.buttons["photo.editor.save"].tap()
        let copy = app.buttons["另存副本"]
        XCTAssertTrue(copy.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["保存到原图"].exists)
        copy.tap()
        XCTAssertTrue(app.staticTexts["已另存副本"].waitForExistence(timeout: 35))
        app.buttons["好"].tap()
        app.buttons["photo.detail.done"].tap()
        app.buttons["review.done"].tap()
        expectation(for: NSPredicate { _, _ in
            Int(count.value as? String ?? "") == (before ?? 0) + 1
        }, evaluatedWith: count)
        waitForExpectations(timeout: 20)
    }

    @MainActor
    func testPreviousGestureRestoresStagedDeletion() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-review.gesture.down", "previous"]
        app.launch()
        waitForCatalogue(app)
        XCTAssertTrue(app.buttons["review.start"].waitForExistence(timeout: 25))
        app.buttons["review.start"].tap()
        let image = app.images["review.image"].firstMatch
        XCTAssertTrue(image.waitForExistence(timeout: 30))
        let progress = app.staticTexts["review.progress"]
        let pending = app.buttons["review.pending"]
        XCTAssertEqual(app.buttons["review.undo"].label, "上一张")
        image.swipeLeft()
        expect(progress, label: "1 /")
        XCTAssertTrue(pending.label.contains("1"))
        XCTAssertTrue(image.waitForExistence(timeout: 20))
        image.swipeDown()
        expect(progress, label: "0 /")
        XCTAssertFalse(pending.isEnabled)
        XCTAssertFalse(app.buttons["review.undo"].isEnabled)
        capture("18-previous-gesture")
        app.buttons["review.keep"].tap()
        expect(progress, label: "1 /")
        app.buttons["review.undo"].tap()
        expect(progress, label: "0 /")
        XCTAssertFalse(pending.isEnabled)
    }

    @MainActor
    func testSwipeUndoFavoritesReviewAndDeletion() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        waitForCatalogue(app)
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
        let workBeforeDeletion = progress.value as? String
        XCTAssertNotNil(workBeforeDeletion)
        let deletedFilename = app.staticTexts["review.filename"].label
        delete.tap()
        pending.tap()
        let commit = app.buttons["pending.delete"]
        XCTAssertTrue(commit.waitForExistence(timeout: 10))
        capture("12-delete-review")
        commit.tap()
        let dialog = systemDialog(app)
        XCTAssertTrue(dialog.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["deletion.status"].exists, "删除确认页必须显示处理状态，不能只禁用整页")
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
        XCTAssertEqual(progress.value as? String, workBeforeDeletion, "删除不得触发全库读取或相似匹配")
        if app.buttons["review.undo"].isEnabled {
            app.buttons["review.undo"].tap()
            XCTAssertNotEqual(app.staticTexts["review.filename"].label, deletedFilename)
            app.buttons["review.keep"].tap()
        }
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: delete)
        waitForExpectations(timeout: 20)
        delete.tap()
        pending.tap()
        XCTAssertTrue(commit.waitForExistence(timeout: 10))
        commit.tap()
        let second = systemDialog(app)
        XCTAssertTrue(second.waitForExistence(timeout: 10))
        second.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] 'Delete' OR label BEGINSWITH '删除'")).firstMatch.tap()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: commit)
        waitForExpectations(timeout: 30)
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(progress.waitForExistence(timeout: 20))
        XCTAssertEqual(progress.value as? String, workBeforeDeletion, "连续删除并回到前台不得全库重扫")
        capture("13-review-after-delete")
        app.navigationBars.buttons["完成"].tap()
        expectation(for: NSPredicate { _, _ in
            Int(count.value as? String ?? count.label) == (originalCount ?? 0) - 2
        }, evaluatedWith: count)
        waitForExpectations(timeout: 20)
    }

    @MainActor
    func testCollectionsDoubleRowsAndCompressionCopy() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        waitForCatalogue(app)
        XCTAssertTrue(app.tabBars.buttons["整理"].waitForExistence(timeout: 20))
        app.tabBars.buttons["整理"].tap()
        let count = app.staticTexts["organize.count"]
        XCTAssertTrue(count.waitForExistence(timeout: 15))
        let before = Int(count.value as? String ?? count.label)
        app.buttons["organize.scope.photos"].tap()
        let layout = app.buttons["browser.layout"]
        XCTAssertTrue(layout.waitForExistence(timeout: 10))
        if layout.label == "双行浏览" { layout.tap() }
        XCTAssertEqual(layout.label, "网格浏览")
        XCTAssertTrue(app.scrollViews["browser.twoRows"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.images["照片预览"].firstMatch.waitForExistence(timeout: 15))
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
    private func waitForCatalogue(_ app: XCUIApplication) {
        let count = app.staticTexts["organize.count"]
        let refresh = app.buttons["library.refresh"]
        expectation(for: NSPredicate { _, _ in
            count.exists && (Int(count.value as? String ?? "") ?? 0) > 0 && refresh.exists && refresh.isEnabled
        }, evaluatedWith: count)
        waitForExpectations(timeout: 30)
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
