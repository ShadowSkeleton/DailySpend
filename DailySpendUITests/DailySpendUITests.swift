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

    /// A typed item is added when the person moves on, without the + button,
    /// and "Select All" is a plain action rather than another highlighted chip.
    @MainActor
    func testItemIsAddedWithoutTappingPlus() throws {
        let splitBillTab = navigationButton(named: "Split Bill")
        XCTAssertTrue(splitBillTab.waitForExistence(timeout: 5))
        splitBillTab.tap()
        app.segmentedControls["split-mode-picker"].buttons["By Item"].tap()

        app.buttons["split-add-person"].tap()
        let nameField = app.alerts.textFields.firstMatch
        XCTAssertTrue(nameField.waitForExistence(timeout: 3))
        nameField.typeText("Alex")
        app.alerts.buttons["Save"].tap()

        let itemName = app.textFields["split-item-name"]
        XCTAssertTrue(itemName.waitForExistence(timeout: 3))
        itemName.tap()
        itemName.typeText("Pizza")
        let price = app.textFields["split-item-price"]
        price.tap()
        price.typeText("20")
        // Leave the row without tapping +.
        app.staticTexts["People"].firstMatch.tap()

        XCTAssertTrue(app.staticTexts["Pizza"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["$20.00 · Everyone · $10.00 each"].exists)
        XCTAssertEqual(itemName.value as? String ?? "", "Item name", "The add row is cleared for the next item")

        let selectAll = app.buttons["item-select-all"]
        XCTAssertEqual(selectAll.label, "Clear")
        selectAll.tap()
        XCTAssertTrue(app.staticTexts["$20.00 · Choose who shares this"].waitForExistence(timeout: 3))
        XCTAssertEqual(selectAll.label, "Select All")
        app.buttons["share-chip-Alex"].tap()
        XCTAssertTrue(app.staticTexts["$20.00 · Alex only"].waitForExistence(timeout: 3))
        attachScreenshot(named: "Item added without plus")
    }

    /// The Scan Receipt control opens the app through this link and starts a
    /// scan; the person still reviews before anything is saved.
    @MainActor
    func testScanLinkOpensTheScannerForReview() throws {
        app.terminate()
        app.launchArguments += ["-ui-test-receipt"]
        app.launch()
        XCTAssertTrue(app.buttons["Add expense"].waitForExistence(timeout: 5))
        navigationButton(named: "Settings").tap()

        app.open(URL(string: "dailyspend://scan")!)
        XCTAssertTrue(app.descendants(matching: .any)["receipt-draft-banner"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.textFields["expense-amount"].value as? String, "42.51")
        app.buttons["Cancel"].tap()
        XCTAssertFalse(app.staticTexts["-$42.51"].waitForExistence(timeout: 2), "Nothing is saved without Save")
    }

    /// Typing in a split puts the hide-keyboard button in the navigation bar,
    /// as New Expense does; nothing floats over the keyboard.
    @MainActor
    func testSplitKeyboardIsPutAwayFromTheNavigationBar() throws {
        let splitBillTab = navigationButton(named: "Split Bill")
        XCTAssertTrue(splitBillTab.waitForExistence(timeout: 5))
        splitBillTab.tap()
        app.segmentedControls["split-mode-picker"].buttons["By Item"].tap()

        let itemName = app.textFields["split-item-name"]
        XCTAssertTrue(itemName.waitForExistence(timeout: 3))
        itemName.tap()
        itemName.typeText("Fries")
        let price = app.textFields["split-item-price"]
        price.tap()
        price.typeText("6")

        let hideKeyboard = app.navigationBars.buttons["keyboard-dismiss"]
        XCTAssertTrue(hideKeyboard.waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["Start a new split"].exists, "The reset button steps aside while typing")
        XCTAssertFalse(app.buttons["split-next-item"].exists)
        attachScreenshot(named: "Split keyboard with navigation bar button")

        hideKeyboard.tap()
        XCTAssertFalse(app.keyboards.element.waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Fries"].waitForExistence(timeout: 3), "Putting the keyboard away adds the typed item")
        XCTAssertTrue(app.buttons["Start a new split"].waitForExistence(timeout: 3))
    }

    /// Plain words fill New Expense with this person's share; nothing saves
    /// until they tap Save.
    @MainActor
    func testQuickAddFillsNewExpenseFromWords() throws {
        let add = app.buttons["Add expense"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()
        let words = app.textViews["quick-entry-field"].exists ? app.textViews["quick-entry-field"] : app.textFields["quick-entry-field"]
        XCTAssertTrue(words.waitForExistence(timeout: 5))
        words.tap()
        words.typeText("lunch with Alex 36, split 3")
        app.buttons["quick-entry-submit"].tap()

        // The rules fill the amount at once; only the category waits for the model.
        let amount = app.textFields["expense-amount"]
        let filled = expectation(for: NSPredicate(format: "value == %@", "12.00"), evaluatedWith: amount)
        wait(for: [filled], timeout: 2)
        XCTAssertTrue(app.descendants(matching: .any)["quick-entry-summary"].exists)
        let note = app.descendants(matching: .any)["expense-note"]
        // A short title first, like a scanned receipt's store name, then the words.
        let noteText = note.value as? String ?? ""
        let title = noteText.components(separatedBy: "\n").first ?? ""
        XCTAssertFalse(title.isEmpty)
        XCTAssertLessThan(title.count, "lunch with Alex 36, split 3".count, noteText)
        XCTAssertTrue(noteText.contains("lunch with Alex 36, split 3"), noteText)
        XCTAssertTrue(app.buttons["Save"].isEnabled)
        sleep(1)
        attachScreenshot(named: "Quick add filled in")

        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.navigationBars["DailySpend"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["-$12.00"].exists, "Nothing is saved without tapping Save")
    }

    /// First-time people see what Quick Add is for, with examples to try.
    @MainActor
    func testQuickAddExamplesShowFirstTimeUsers() throws {
        app.terminate()
        app.launchArguments += ["-quickAddUsed", "NO"]
        app.launch()
        app.buttons["Add expense"].tap()
        XCTAssertTrue(app.staticTexts["Quick Add"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Type or say what you spent in your own words, and the form below fills itself in."].exists)
        let example = app.buttons["quick-example-1"]
        XCTAssertTrue(example.exists)
        XCTAssertEqual(example.label, "Lunch 36, split 3")
        sleep(1)
        attachScreenshot(named: "Quick Add for first-time users")
        example.tap()
        let filled = expectation(for: NSPredicate(format: "value == %@", "12.00"),
                                 evaluatedWith: app.textFields["expense-amount"])
        wait(for: [filled], timeout: 2)
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

    /// Part C of the 2.0 manual plan, read by the real on-device model from
    /// the test receipt images. Skipped where Apple Intelligence isn't available.
    @MainActor
    func testQuickSplitScansRealReceipts() throws {
        let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("docs/test-receipts")
        let files = ["01-restaurant-suggested-tip", "16-restaurant-tip-after-tax",
                     "02-restaurant-tip-charged", "03-grocery-long-coupons"]
            .map { folder.appendingPathComponent("\($0).jpg").path }
        app.terminate()
        app.launchArguments += ["-ui-test-receipt-files", files.joined(separator: ",")]
        app.launch()

        let splitBillTab = navigationButton(named: "Split Bill")
        XCTAssertTrue(splitBillTab.waitForExistence(timeout: 5))
        splitBillTab.tap()
        let total = app.textFields["total-bill-amount"]
        let banner = app.descendants(matching: .any)["receipt-draft-banner"]

        func scan(expectingTotal expected: String) throws {
            let scan = app.buttons["scan-receipt"].firstMatch
            for _ in 0..<4 where !scan.isHittable { app.scrollViews.firstMatch.swipeDown() }
            scan.tap()
            if app.buttons["Choose from Photos"].waitForExistence(timeout: 1) {
                app.buttons["Choose from Photos"].tap()
            }
            let filled = NSPredicate(format: "value == %@", expected)
            let read = expectation(for: filled, evaluatedWith: total)
            if XCTWaiter().wait(for: [read], timeout: 60) != .completed {
                if app.alerts.firstMatch.exists || app.staticTexts["Only the total was read. Turn on Apple Intelligence to read items."].exists {
                    throw XCTSkip("Apple Intelligence isn't available on this simulator.")
                }
                XCTFail("Expected a total of \(expected), got \(total.value as? String ?? "nothing")")
            }
            XCTAssertTrue(banner.waitForExistence(timeout: 3))
            // The total alone is right, but the checks below need the model's
            // reading of tips and items.
            if app.staticTexts["Only the total was read. Turn on Apple Intelligence to read items."].exists {
                throw XCTSkip("The on-device model couldn't run on this simulator; the total was read without it.")
            }
        }

        // C01: the bill leaves the tip blank, so nothing is chosen for the payer.
        try scan(expectingTotal: "42.51")
        let hint = app.descendants(matching: .any)["tip-undecided-hint"]
        for _ in 0..<4 where !hint.isHittable { app.scrollViews.firstMatch.swipeUp() }
        XCTAssertTrue(hint.exists)
        XCTAssertTrue(app.staticTexts["Not chosen"].exists)
        XCTAssertTrue(app.staticTexts["Before tip"].exists)
        XCTAssertTrue(app.staticTexts["$21.26"].exists, "$42.51 between 2 before the tip")
        // The receipt's tip guide becomes the choices: 18% and 20% with its amounts.
        XCTAssertFalse(app.buttons["10%"].exists)
        app.buttons["18%, $7.02"].tap()
        XCTAssertTrue(app.staticTexts["$7.02"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["20%, $7.80"].exists)
        XCTAssertTrue(app.staticTexts["From the receipt’s tip guide"].exists)
        XCTAssertFalse(hint.exists)
        attachScreenshot(named: "C01 tip chosen after scan")

        // C01a: this restaurant figures its tip guide on the total after tax;
        // the choices are its own, so the split matches the slip exactly.
        try scan(expectingTotal: "44.10")
        let eighteen = app.buttons["18%, $7.94"]
        for _ in 0..<4 where !eighteen.isHittable { app.scrollViews.firstMatch.swipeUp() }
        XCTAssertTrue(app.buttons["15%, $6.62"].exists)
        XCTAssertTrue(app.buttons["20%, $8.82"].exists)
        eighteen.tap()
        XCTAssertTrue(app.staticTexts["$7.94"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["$26.02"].exists, "($44.10 + $7.94) between 2")
        attachScreenshot(named: "C01a tip guide after tax")

        // C02: the charged tip becomes a fixed tip and isn't counted twice.
        try scan(expectingTotal: "52.26")
        let fixedTip = app.textFields["Fixed tip amount"]
        for _ in 0..<4 where !fixedTip.isHittable { app.scrollViews.firstMatch.swipeUp() }
        XCTAssertTrue(fixedTip.exists)
        XCTAssertTrue(app.staticTexts["$30.63"].exists, "($52.26 + $9.00) between 2")
        attachScreenshot(named: "C02 charged tip")

        // C03: a grocery receipt sets the tip to None.
        try scan(expectingTotal: "78.02")
        for _ in 0..<4 where !app.staticTexts["$39.01"].isHittable { app.scrollViews.firstMatch.swipeUp() }
        XCTAssertTrue(app.staticTexts["$39.01"].exists, "$78.02 between 2 with no tip")
        XCTAssertFalse(app.staticTexts["Before tip"].exists)
        attachScreenshot(named: "C03 grocery without tip")

        // C04: recording my share carries the share, category, and store.
        app.buttons["Record My Share"].tap()
        let amount = app.textFields["expense-amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        XCTAssertEqual(amount.value as? String, "39.01")
        XCTAssertTrue(app.staticTexts["Grocery"].exists || app.buttons["Grocery"].exists)
        let note = app.descendants(matching: .any)["expense-note"]
        XCTAssertTrue((note.value as? String ?? "").hasPrefix("Green Basket Market"))
        attachScreenshot(named: "C04 record my share")
        app.buttons["Cancel"].tap()

        // C05: Clear Form empties the total, the banner, and the tip.
        let reset = app.buttons["Start a new split"]
        XCTAssertTrue(reset.waitForExistence(timeout: 5))
        reset.tap()
        app.alerts.buttons["Clear Form"].tap()
        XCTAssertTrue(banner.waitForNonExistence(timeout: 3))
        XCTAssertEqual(total.value as? String ?? "", "0", "The empty field shows its placeholder")
    }

    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
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

        // A quick look at this month on top: a big more-or-less number and one short line.
        XCTAssertTrue(app.descendants(matching: .any)["insights-glance"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["insights-first-month"].exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label ENDSWITH ' So Far'")).firstMatch.exists)
        let headline = app.staticTexts["insights-headline"]
        XCTAssertTrue(headline.label.hasSuffix(" more") || headline.label.hasSuffix(" less"), headline.label)
        XCTAssertTrue(app.staticTexts["than this time last month"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["insights-quick-line"].label.hasPrefix("You’ve spent"))
        XCTAssertFalse(app.staticTexts["insights-summary-text"].exists, "The long summary waits under Details")
        XCTAssertTrue(app.descendants(matching: .any)["trend-period-total"].exists, "The graph shows the period's total and change")
        sleep(3)

        let insightsAttachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        insightsAttachment.name = "Sample Insights"
        insightsAttachment.lifetime = .keepAlways
        add(insightsAttachment)

        app.buttons["Details"].tap()
        XCTAssertTrue(app.staticTexts["insights-summary-text"].waitForExistence(timeout: 5))
        sleep(1)
        attachScreenshot(named: "Sample Insights, details")
        app.buttons["Details"].tap()

        // The period buttons drive the graph; the glance stays on this month.
        let thisMonthTotal = app.descendants(matching: .any)["trend-period-total"].label
        app.buttons["Last Month"].tap()
        let lastMonthTotal = app.descendants(matching: .any)["trend-period-total"]
        XCTAssertTrue(lastMonthTotal.waitForExistence(timeout: 5))
        XCTAssertNotEqual(lastMonthTotal.label, thisMonthTotal)
        XCTAssertTrue(headline.label.hasSuffix(" more") || headline.label.hasSuffix(" less"))
        sleep(1)
        attachScreenshot(named: "Sample Insights, last month")
    }

    /// Someone in their first month sees this month's spending, not a
    /// comparison with nothing.
    @MainActor
    func testInsightsWelcomesAFirstMonth() throws {
        let add = app.buttons["Add expense"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()
        let words = app.textViews["quick-entry-field"].exists ? app.textViews["quick-entry-field"] : app.textFields["quick-entry-field"]
        XCTAssertTrue(words.waitForExistence(timeout: 5))
        words.tap()
        words.typeText("Lunch at KFC 25")
        app.buttons["quick-entry-submit"].tap()
        let amount = app.textFields["expense-amount"]
        wait(for: [expectation(for: NSPredicate(format: "value == %@", "25.00"), evaluatedWith: amount)], timeout: 2)
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["-$25.00"].waitForExistence(timeout: 5))

        navigationButton(named: "Insights").tap()
        XCTAssertTrue(app.descendants(matching: .any)["insights-glance"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["insights-first-month"].exists)
        XCTAssertEqual(app.staticTexts["insights-headline"].label, "$25", "A first month shows its total, not a change from zero")
        let quickLine = app.descendants(matching: .any)["insights-quick-line"].label
        XCTAssertTrue(quickLine.contains("1 expense") && quickLine.contains("Most on Food"), quickLine)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label ENDSWITH ' So Far'")).firstMatch.exists)
        sleep(1)
        attachScreenshot(named: "Insights in a first month")
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

    // MARK: - 2.0 tour

    private enum WhatsNewArgument {
        static let show = "-show-whats-new"
    }

    private func launchTour(_ extra: [String] = [], language: String = "en", locale: String = "en_US") {
        app.terminate()
        app.launchArguments = ["-ui-testing", WhatsNewArgument.show, "-AppleLanguages", "(\(language))", "-AppleLocale", locale] + extra
        app.launch()
    }

    /// Walks every page, saving a screenshot of each, and returns the titles.
    @discardableResult
    private func walkTour(named name: String, pages: Int) -> [String] {
        var titles: [String] = []
        let tour = app.otherElements["whats-new"]
        for page in 1...pages {
            // Each page's title is its own; wait for the new one to settle.
            let title = app.staticTexts.matching(identifier: "whats-new-title").allElementsBoundByIndex
                .first { $0.isHittable }
            titles.append(title?.label ?? "")
            Thread.sleep(forTimeInterval: 2.6)
            attachScreenshot(named: "\(name) \(page)")
            let next = app.buttons["whats-new-continue"]
            if page < pages {
                XCTAssertTrue(next.waitForExistence(timeout: 3))
                next.tap()
                Thread.sleep(forTimeInterval: 0.6)
            }
        }
        XCTAssertTrue(tour.exists)
        return titles
    }

    @MainActor
    func testWhatsNewWelcomesANewInstall() throws {
        launchTour()
        XCTAssertTrue(app.staticTexts["Spending, made clear"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["whats-new-back-up"].exists)

        let titles = walkTour(named: "Welcome tour", pages: 6)
        XCTAssertEqual(titles, [
            "Spending, made clear", "Scan a receipt", "Split a bill from the receipt",
            "Add in plain words", "Siri, Shortcuts, and Controls", "Your month at a glance"
        ])
        XCTAssertEqual(app.buttons["whats-new-continue"].label, "Get Started")
        XCTAssertTrue(app.staticTexts["You can see this again in Settings."].exists)
        app.buttons["whats-new-continue"].tap()

        XCTAssertTrue(app.buttons["add-first-expense"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.otherElements["whats-new"].exists)
    }

    @MainActor
    func testWhatsNewOffersABackupAfterAnUpdate() throws {
        launchTour(["-seed-demo-data"])
        let backUp = app.buttons["whats-new-back-up"]
        XCTAssertTrue(backUp.waitForExistence(timeout: 5))
        let title = app.staticTexts.matching(identifier: "whats-new-title").firstMatch
        XCTAssertTrue(title.label.hasPrefix("Your ") && title.label.hasSuffix(" expenses are all here"), title.label)
        Thread.sleep(forTimeInterval: 2.6)
        attachScreenshot(named: "Update tour 1 backup")

        // Back Up Now opens the same encrypted backup as Settings.
        backUp.tap()
        XCTAssertTrue(app.navigationBars["Encrypt Backup"].waitForExistence(timeout: 5))
        attachScreenshot(named: "Update tour backup passphrase")
        app.buttons["Cancel"].tap()
        XCTAssertTrue(backUp.waitForExistence(timeout: 5))

        app.buttons["whats-new-not-now"].tap()
        XCTAssertTrue(app.staticTexts["Scan a receipt"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["NEW IN 2.0"].exists)
        app.buttons["whats-new-skip"].tap()
        XCTAssertTrue(app.staticTexts["Recent Transactions"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testWhatsNewWaitsWhenAWidgetOpensTheApp() throws {
        app.terminate()
        app.launchArguments += [WhatsNewArgument.show]
        app.open(URL(string: "dailyspend://add")!)
        XCTAssertTrue(app.navigationBars["New Expense"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.otherElements["whats-new"].exists)
        app.buttons["Cancel"].tap()
        // Still this visit: the tour waits for the next ordinary launch.
        XCTAssertTrue(app.navigationBars["DailySpend"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.otherElements["whats-new"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testWhatsNewCanBeOpenedAgainFromSettings() throws {
        // Ordinary test launches never show the tour by themselves.
        XCTAssertFalse(app.otherElements["whats-new"].waitForExistence(timeout: 2))
        navigationButton(named: "Settings").tap()
        let replay = app.buttons["whats-new-replay"]
        // It sits near the end of Settings, below the first screen.
        for _ in 0..<6 where !replay.isHittable { app.swipeUp() }
        XCTAssertTrue(replay.waitForExistence(timeout: 5))
        replay.tap()
        XCTAssertTrue(app.staticTexts["Scan a receipt"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["whats-new-back-up"].exists)
        app.buttons["whats-new-skip"].tap()
        XCTAssertTrue(replay.waitForExistence(timeout: 5))
    }

    @MainActor
    func testWhatsNewInChinese() throws {
        launchTour(["-seed-demo-data"], language: "zh-Hans", locale: "zh_CN")
        XCTAssertTrue(app.buttons["whats-new-back-up"].waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 2.6)
        attachScreenshot(named: "Chinese tour 1")
        app.buttons["whats-new-not-now"].tap()
        walkTour(named: "Chinese tour", pages: 5)
        XCTAssertEqual(app.buttons["whats-new-continue"].label, "开始使用")
    }

    @MainActor
    func testWhatsNewAtTheLargestTextSize() throws {
        launchTour(["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        XCTAssertTrue(app.buttons["whats-new-continue"].waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 2.6)
        attachScreenshot(named: "Tour largest text 1")
        app.buttons["whats-new-continue"].tap()
        Thread.sleep(forTimeInterval: 2.6)
        attachScreenshot(named: "Tour largest text 2")
        XCTAssertTrue(app.buttons["whats-new-continue"].isHittable)
    }
}
