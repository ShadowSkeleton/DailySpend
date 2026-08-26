import XCTest

final class DailySpendUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // Keep UI automation deterministic and entirely separate from real data.
        app.launchArguments = ["-ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
    }

    @MainActor
    func testNewUserSeesFastExpenseAndSplitActions() throws {
        XCTAssertTrue(app.buttons["add-first-expense"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["start-split-bill"].exists)
    }

    @MainActor
    func testSplitBillOffersQuickAndItemMethods() throws {
        let splitBillTab = app.tabBars.buttons["Split Bill"]
        XCTAssertTrue(splitBillTab.waitForExistence(timeout: 5))
        splitBillTab.tap()

        let splitModePicker = app.segmentedControls["split-mode-picker"]
        XCTAssertTrue(splitModePicker.waitForExistence(timeout: 5))
        XCTAssertTrue(splitModePicker.buttons["Quick Split"].exists)
        XCTAssertTrue(splitModePicker.buttons["By Item"].exists)

        // Return the content scroll view to its visual starting point before
        // capturing the journey evidence; this also catches clipped controls.
        let content = app.scrollViews.firstMatch
        content.swipeDown()
        content.swipeDown()

        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "Split Bill"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testSettingsExposesICloudAndPrivateBackupActions() throws {
        let settingsTab = app.tabBars.buttons["Settings"]
        XCTAssertTrue(settingsTab.waitForExistence(timeout: 5))
        settingsTab.tap()

        XCTAssertTrue(app.buttons["refresh-icloud-status"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["create-json-backup"].exists)

        // Privacy settings are intentionally placed before backup controls.
        // Scroll like a person would, then assert the restore action is still
        // discoverable and reachable rather than assuming it fits above the
        // fold on every supported phone size.
        app.collectionViews.firstMatch.swipeUp()
        XCTAssertTrue(app.buttons["restore-json-backup"].waitForExistence(timeout: 3))

        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "Settings Data Safety"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testDebugDemoDataMakesDashboardAndInsightsTestable() throws {
        // The sample-data path is Debug-only, opt-in, and requires an empty
        // store. UI tests run in memory, so this cannot touch a person's data.
        app.terminate()
        app.launchArguments = ["-ui-testing", "-seed-demo-data", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Recent Transactions"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Export expenses"].exists)

        let homeAttachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        homeAttachment.name = "Sample Dashboard"
        homeAttachment.lifetime = .keepAlways
        add(homeAttachment)

        let insightsTab = app.tabBars.buttons["Insights"]
        XCTAssertTrue(insightsTab.waitForExistence(timeout: 5))
        insightsTab.tap()
        XCTAssertTrue(app.navigationBars["Insights"].waitForExistence(timeout: 5))

        let insightsAttachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        insightsAttachment.name = "Sample Insights"
        insightsAttachment.lifetime = .keepAlways
        add(insightsAttachment)
    }

    @MainActor
    func testNumericExpenseKeyboardHasAnAccessibleDismissAction() throws {
        let addExpense = app.buttons["Add expense"]
        XCTAssertTrue(addExpense.waitForExistence(timeout: 5))
        addExpense.tap()

        let amountField = app.textFields["0"].firstMatch
        XCTAssertTrue(amountField.waitForExistence(timeout: 5))
        amountField.tap()

        let dismissKeyboard = app.buttons["keyboard-dismiss"]
        XCTAssertTrue(dismissKeyboard.waitForExistence(timeout: 5))

        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "Keyboard Dismiss Control"
        attachment.lifetime = .keepAlways
        add(attachment)

        dismissKeyboard.tap()
        XCTAssertFalse(app.keyboards.element.waitForExistence(timeout: 2))

        app.buttons["Cancel"].tap()
    }
}
