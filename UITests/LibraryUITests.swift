import XCTest

final class LibraryUITests: XCTestCase {
    @MainActor
    func testLibraryScreensAndSelection() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        if app.buttons["选择照片访问范围"].waitForExistence(timeout: 3) {
            app.buttons["选择照片访问范围"].tap()
            let permissions = XCUIApplication(bundleIdentifier: "com.apple.springboard")
            let allow = permissions.buttons.matching(NSPredicate(format:
                "label CONTAINS[c] 'Full Access' OR label CONTAINS[c] 'All Photos' OR label CONTAINS '完全访问' OR label CONTAINS '所有照片'")).firstMatch
            XCTAssertTrue(allow.waitForExistence(timeout: 10))
            allow.tap()
        }
        XCTAssertTrue(app.staticTexts["清理项目"].waitForExistence(timeout: 30))
        capture("01-cleanup", app: app)
        app.buttons["library.all"].tap()
        XCTAssertTrue(app.navigationBars["全部项目"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["选择待删"].firstMatch.waitForExistence(timeout: 15))
        capture("02-photos", app: app)
        app.buttons["选择待删"].firstMatch.tap()
        XCTAssertTrue(app.buttons["library.delete"].waitForExistence(timeout: 5))
        capture("03-selection", app: app)
        app.tabBars.buttons["搜索"].tap()
        XCTAssertTrue(app.navigationBars["搜索"].waitForExistence(timeout: 10))
        capture("04-search", app: app)
        app.tabBars.buttons["清理"].tap()
        app.buttons["取消选择"].firstMatch.tap()
        app.navigationBars.buttons["相册整理"].tap()
        app.buttons["library.analyze"].tap()
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.buttons["library.analyze"].waitForExistence(timeout: 60))
        let metric = app.otherElements["library.metric.已分析"]
        XCTAssertEqual(metric.value as? String, "3")
        capture("05-analyzed", app: app)
        app.buttons["library.all"].tap()
        let photoCount = app.buttons.matching(identifier: "选择待删").count
        app.buttons["选择待删"].firstMatch.tap()
        app.buttons["library.delete"].tap()
        let appDialog = app.alerts.firstMatch
        let dialog = appDialog.waitForExistence(timeout: 5) ? appDialog
            : XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
        XCTAssertTrue(dialog.waitForExistence(timeout: 10))
        capture("06-system-delete-confirmation", app: app)
        let confirm = dialog.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] 'Delete' OR label BEGINSWITH '删除'")).firstMatch
        XCTAssertTrue(confirm.exists)
        confirm.tap()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.buttons["library.delete"])
        waitForExpectations(timeout: 20)
        expectation(for: NSPredicate { _, _ in
            app.buttons.matching(identifier: "选择待删").count == photoCount - 1
        }, evaluatedWith: app)
        waitForExpectations(timeout: 15)
        capture("07-after-delete", app: app)
    }

    @MainActor
    private func capture(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
