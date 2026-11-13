import XCTest

final class LibraryUITests: XCTestCase {
    @MainActor
    func testLibraryScreensAndSelection() {
        let app = XCUIApplication()
        app.launch()
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
    }

    @MainActor
    private func capture(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
