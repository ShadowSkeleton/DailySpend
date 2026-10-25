import XCTest

final class DailySpendUITests: XCTestCase {
    private var app: XCUIApplication!

    private func navigationButton(named label: String) -> XCUIElement {
        let compactTabButton = app.tabBars.buttons[label]
        if compactTabButton.waitForExistence(timeout: 2) {
            return compactTabButton
        }

        // iPad presents SwiftUI's adaptive tab bar across the top, where its
        // destinations are exposed as ordinary buttons instead of a tab bar.
        return app.buttons[label].firstMatch
    }

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
    func testWidgetQuickAddOpensOnceFromAnotherTabAndColdLaunch() throws {
        navigationButton(named: "Settings").tap()
        XCUIDevice.shared.system.open(URL(string: "dailyspend://add")!)
        XCTAssertTrue(app.navigationBars["New Expense"].waitForExistence(timeout: 5))
        XCUIDevice.shared.system.open(URL(string: "dailyspend://add")!)
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.navigationBars["DailySpend"].waitForExistence(timeout: 5))
        app.terminate()
        app.open(URL(string: "dailyspend://add")!)
        XCTAssertTrue(app.navigationBars["New Expense"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()
        XCTAssertFalse(app.navigationBars["New Expense"].exists)
    }

    @MainActor
    func testWidgetDashboardReturnsToHomeOnFirstOpen() throws {
        navigationButton(named: "Insights").tap()
        XCUIDevice.shared.system.open(URL(string: "dailyspend://home")!)
        XCTAssertTrue(app.navigationBars["DailySpend"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars["New Expense"].exists)
    }

    @MainActor
    func testWidgetQuickAddDoesNotExposeContentBeforeAuthentication() throws {
        app.terminate()
        app.launchArguments += ["-isAppLockEnabled", "YES"]
        app.launch()
        app.open(URL(string: "dailyspend://add")!)
        // The system passcode/biometric prompt can cover our lock title. Assert
        // the security boundary, not which authentication UI iOS chooses.
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "Quick Add Authentication Gate"
        attachment.lifetime = .keepAlways
        add(attachment)
        add(XCTAttachment(string: app.debugDescription))
        XCTAssertEqual(app.state, .runningForeground)
        XCTAssertFalse(app.navigationBars["New Expense"].exists)
        XCTAssertFalse(app.buttons["add-first-expense"].exists)
    }

    @MainActor
    func testSplitBillOffersQuickAndItemMethods() throws {
        let splitBillTab = navigationButton(named: "Split Bill")
        XCTAssertTrue(splitBillTab.waitForExistence(timeout: 5))
        splitBillTab.tap()

        let splitModePicker = app.segmentedControls["split-mode-picker"]
        XCTAssertTrue(splitModePicker.waitForExistence(timeout: 5))
        XCTAssertTrue(splitModePicker.buttons["Quick Split"].exists)
        XCTAssertTrue(splitModePicker.buttons["By Item"].exists)

        let currency = app.staticTexts["total-bill-currency"]
        let amount = app.textFields["total-bill-amount"]
        XCTAssertTrue(currency.waitForExistence(timeout: 3))
        XCTAssertTrue(amount.exists)
        XCTAssertLessThanOrEqual(amount.frame.minX - currency.frame.maxX, 8)

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
    func testItemizedSplitKeepsEveryTipChoiceReachable() throws {
        let splitBillTab = navigationButton(named: "Split Bill")
        XCTAssertTrue(splitBillTab.waitForExistence(timeout: 5))
        splitBillTab.tap()

        let splitModePicker = app.segmentedControls["split-mode-picker"]
        XCTAssertTrue(splitModePicker.waitForExistence(timeout: 5))
        splitModePicker.buttons["By Item"].tap()

        let noTip = app.buttons["tip-none"]
        let customTip = app.buttons["tip-custom"]
        for _ in 0..<4 where !customTip.isHittable || !noTip.isHittable {
            app.scrollViews.firstMatch.swipeUp()
        }

        XCTAssertTrue(noTip.isHittable)
        XCTAssertTrue(customTip.isHittable)

        // Custom holds both a percentage and a fixed amount.
        customTip.tap()
        let customType = app.segmentedControls["custom-tip-type"]
        XCTAssertTrue(customType.waitForExistence(timeout: 3))
        XCTAssertTrue(customType.buttons["%"].exists)
        XCTAssertTrue(customType.buttons["$"].exists)
    }

    @MainActor
    func testHomeScanFillsANewExpenseForReview() throws {
        app.terminate()
        app.launchArguments += ["-ui-test-receipt"]
        app.launch()

        let scan = app.buttons["home-scan-receipt"]
        XCTAssertTrue(scan.waitForExistence(timeout: 5))
        scan.tap()
        if app.buttons["Choose from Photos"].waitForExistence(timeout: 1) {
            app.buttons["Choose from Photos"].tap()
        }

        XCTAssertTrue(app.descendants(matching: .any)["receipt-draft-banner"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["expense-amount"].value as? String, "42.51")

        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "Scanned receipt review"
        attachment.lifetime = .keepAlways
        add(attachment)

        app.buttons["Save"].tap()
        XCTAssertTrue(app.navigationBars["DailySpend"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["-$42.51"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testScannedReceiptFillsBothSplitModes() throws {
        app.terminate()
        app.launchArguments += ["-ui-test-receipt"]
        app.launch()

        let splitBillTab = navigationButton(named: "Split Bill")
        XCTAssertTrue(splitBillTab.waitForExistence(timeout: 5))
        splitBillTab.tap()

        // Quick Split takes the bill total.
        let quickScan = app.buttons["scan-receipt"].firstMatch
        XCTAssertTrue(quickScan.waitForExistence(timeout: 5))
        quickScan.tap()
        XCTAssertEqual(app.textFields["total-bill-amount"].value as? String, "42.51")

        // By Item takes every line, tax included.
        app.segmentedControls["split-mode-picker"].buttons["By Item"].tap()
        let itemScan = app.buttons["scan-receipt"].firstMatch
        XCTAssertTrue(itemScan.waitForExistence(timeout: 5))
        itemScan.tap()
        XCTAssertTrue(app.staticTexts["Spicy Beef Noodles"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label == %@", "Dumplings")).count, 2, "Two dumplings become two assignable lines")

        let noTip = app.buttons["tip-none"]
        for _ in 0..<5 where !noTip.isHittable { app.scrollViews.firstMatch.swipeUp() }
        noTip.tap()
        XCTAssertTrue(app.staticTexts["$42.51"].waitForExistence(timeout: 3))

        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "Scanned itemized split"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testSettingsExposesICloudAndPrivateBackupActions() throws {
        let settingsTab = navigationButton(named: "Settings")
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
    func testAboutDailySpendOpensOnFirstTap() throws {
        let settingsTab = navigationButton(named: "Settings")
        XCTAssertTrue(settingsTab.waitForExistence(timeout: 5))
        settingsTab.tap()

        let about = app.buttons["about-dailyspend"]
        for _ in 0..<4 where !about.exists {
            app.collectionViews.firstMatch.swipeUp()
        }
        XCTAssertTrue(about.waitForExistence(timeout: 3))

        about.tap()
        XCTAssertTrue(app.navigationBars["About DailySpend"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["DailySpend"].exists)

        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "About DailySpend"
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

        let insightsTab = navigationButton(named: "Insights")
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

        let amountField = app.textFields["expense-amount"].firstMatch
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

    @MainActor
    private func addLongNoteExpense() throws {
        app.buttons["Add expense"].tap()
        let amount = app.textFields["expense-amount"].firstMatch
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        amount.tap()
        amount.typeText("57.50")
        let dismissKeyboard = app.buttons["keyboard-dismiss"]
        if dismissKeyboard.exists { dismissKeyboard.tap() }
        let note = app.descendants(matching: .any).matching(identifier: "expense-note").firstMatch
        for _ in 0..<4 where !note.isHittable { app.scrollViews.firstMatch.swipeUp() }
        XCTAssertTrue(note.isHittable)
        note.tap()
        note.typeText("Split with 2 people · Total $115.00\nMy share $57.50\nDinner with friends and several shared dishes.")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.navigationBars["DailySpend"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testTransactionCardOpensOnFirstTapAcrossItsEntireArea() throws {
        try addLongNoteExpense()
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "transaction-")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Expanded transaction note"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        for point in [CGVector(dx: 0.92, dy: 0.85), CGVector(dx: 0.15, dy: 0.2),
                      CGVector(dx: 0.55, dy: 0.5), CGVector(dx: 0.92, dy: 0.85), CGVector(dx: 0.5, dy: 0.5)] {
            row.coordinate(withNormalizedOffset: point).tap()
            XCTAssertTrue(app.navigationBars["Edit Expense"].waitForExistence(timeout: 3))
            app.buttons["Cancel"].tap()
            XCTAssertTrue(app.navigationBars["DailySpend"].waitForExistence(timeout: 3))
        }
        row.swipeLeft()
        let deletion = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        deletion.name = "Destructive swipe action"
        deletion.lifetime = .keepAlways
        add(deletion)
    }

    @MainActor
    func testWidgetQuickAddWaitsForExistingEditToDismiss() throws {
        try addLongNoteExpense()
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "transaction-")).firstMatch
        row.tap()
        XCTAssertTrue(app.navigationBars["Edit Expense"].waitForExistence(timeout: 3))
        // XCUIApplication.open relaunches the app and destroys its in-memory
        // test store/draft. Deliver a real warm URL through the system instead.
        XCUIDevice.shared.system.open(URL(string: "dailyspend://add")!)
        XCUIDevice.shared.system.open(URL(string: "dailyspend://add")!)
        XCTAssertTrue(app.navigationBars["Edit Expense"].exists)
        XCTAssertFalse(app.navigationBars["New Expense"].exists)
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.navigationBars["New Expense"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.navigationBars["DailySpend"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "transaction-")).count, 1)
    }

    @MainActor
    func testAboutRemainsReadableAtAccessibilityTextSize() throws {
        app.terminate()
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        navigationButton(named: "Settings").tap()
        let about = app.buttons["about-dailyspend"]
        for _ in 0..<8 where !about.isHittable { app.collectionViews.firstMatch.swipeUp() }
        XCTAssertTrue(about.isHittable)
        about.tap()
        XCTAssertTrue(app.navigationBars["About DailySpend"].waitForExistence(timeout: 3))
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "About accessibility text"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        let support = app.buttons["contact-support"]
        for _ in 0..<12 where !support.isHittable { app.collectionViews.firstMatch.swipeUp() }
        XCTAssertTrue(support.isHittable)
    }
}
