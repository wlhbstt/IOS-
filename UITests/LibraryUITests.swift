import XCTest

final class LibraryUITests: XCTestCase {
    @MainActor
    func testLibraryScreensAndSelection() {
        continueAfterFailure = false
        let app = XCUIApplication()
        addUIInterruptionMonitor(withDescription: "Photo library access") { alert in
            let allow = alert.buttons.matching(NSPredicate(format:
                "label CONTAINS[c] 'Full Access' OR label CONTAINS[c] 'All Photos' OR label CONTAINS '完全访问' OR label CONTAINS '所有照片'")).firstMatch
            guard allow.exists else { return false }
            allow.tap()
            return true
        }
        app.launch()
        if app.buttons["选择照片访问范围"].waitForExistence(timeout: 3) {
            app.buttons["选择照片访问范围"].tap()
            app.activate()
            for permissions in [app, XCUIApplication(bundleIdentifier: "com.apple.springboard")] {
                let allow = permissions.buttons.matching(NSPredicate(format:
                    "label CONTAINS[c] 'Full Access' OR label CONTAINS[c] 'All Photos' OR label CONTAINS '完全访问' OR label CONTAINS '所有照片'")).firstMatch
                if allow.waitForExistence(timeout: 3) { allow.tap(); break }
            }
            if !app.staticTexts["清理项目"].exists { app.tap() }
        }
        let homeReady = app.staticTexts["清理项目"].waitForExistence(timeout: 30)
        if !homeReady {
            capture("00-permission-failure")
            print(app.debugDescription)
            print(XCUIApplication(bundleIdentifier: "com.apple.springboard").debugDescription)
        }
        XCTAssertTrue(homeReady)
        let analyzedMetric = app.otherElements["library.metric.已分析"]
        let pendingMetric = app.otherElements["library.metric.待分析"]
        XCTAssertTrue(pendingMetric.waitForExistence(timeout: 10))
        let analyzedBefore = Int(analyzedMetric.value as? String ?? "")
        let pendingBefore = Int(pendingMetric.value as? String ?? "")
        XCTAssertNotNil(analyzedBefore)
        XCTAssertNotNil(pendingBefore)
        let expectedAnalyzed = (analyzedBefore ?? 0) + (pendingBefore ?? 0)
        XCTAssertGreaterThan(expectedAnalyzed, 0)
        capture("01-cleanup")
        app.buttons["library.all"].tap()
        XCTAssertTrue(app.navigationBars["全部项目"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["选择待删"].firstMatch.waitForExistence(timeout: 15))
        let previewReady = app.images["照片预览"].firstMatch.waitForExistence(timeout: 30)
        if !previewReady { print(app.debugDescription) }
        XCTAssertTrue(previewReady)
        capture("02-photos")
        app.buttons["选择待删"].firstMatch.tap()
        XCTAssertTrue(app.buttons["library.delete"].waitForExistence(timeout: 5))
        capture("03-selection")
        app.tabBars.buttons["搜索"].tap()
        XCTAssertTrue(app.navigationBars["搜索"].waitForExistence(timeout: 10))
        capture("04-search")
        app.tabBars.buttons["清理"].tap()
        app.buttons["取消选择"].firstMatch.tap()
        app.navigationBars.buttons["相册整理"].tap()
        app.buttons["library.analyze"].tap()
        XCTAssertTrue(app.buttons["暂停扫描"].waitForExistence(timeout: 5)
            || analyzedMetric.value as? String == "\(expectedAnalyzed)")
        XCUIDevice.shared.press(.home)
        app.activate()
        let completedAnalysis = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            analyzedMetric.value as? String == "\(expectedAnalyzed)"
        }, object: analyzedMetric)
        let analysisResult = XCTWaiter.wait(for: [completedAnalysis], timeout: 90)
        capture("05-analyzed")
        if analysisResult != .completed { print(app.debugDescription) }
        XCTAssertEqual(analysisResult, .completed)
        XCTAssertTrue(app.buttons["library.analyze"].exists)
        app.buttons["library.all"].tap()
        let photoCount = app.buttons.matching(identifier: "选择待删").count
        app.buttons["选择待删"].firstMatch.tap()
        app.buttons["library.delete"].tap()
        let appDialog = app.alerts.firstMatch
        let dialog = appDialog.waitForExistence(timeout: 5) ? appDialog
            : XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
        XCTAssertTrue(dialog.waitForExistence(timeout: 10))
        capture("06-system-delete-confirmation")
        let confirm = dialog.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] 'Delete' OR label BEGINSWITH '删除'")).firstMatch
        XCTAssertTrue(confirm.exists)
        confirm.tap()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.buttons["library.delete"])
        waitForExpectations(timeout: 20)
        expectation(for: NSPredicate { _, _ in
            app.buttons.matching(identifier: "选择待删").count == photoCount - 1
        }, evaluatedWith: app)
        waitForExpectations(timeout: 15)
        capture("07-after-delete")
    }

    @MainActor
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
