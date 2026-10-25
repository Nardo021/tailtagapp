import XCTest

final class SmartEntryUITests: XCTestCase {
    private var app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-UITestReset", "-UITestSeedPhoto"]
        app.launch()
    }

    func testAddReopenAndEditSmartEntry() throws {
        if app.buttons["Get Started"].waitForExistence(timeout: 8) {
            app.buttons["Get Started"].tap()
            XCTAssertTrue(app.staticTexts["Choose Your Style"].waitForExistence(timeout: 5))
            app.buttons["Continue"].tap()
            XCTAssertTrue(app.staticTexts["App Icon"].waitForExistence(timeout: 5))
            app.buttons["Continue"].tap()
            XCTAssertTrue(app.buttons["Start Spotting"].waitForExistence(timeout: 5))
            app.buttons["Start Spotting"].tap()
        }

        let add = app.buttons["add-aircraft"]
        XCTAssertTrue(add.waitForExistence(timeout: 10), "Add Aircraft did not appear after onboarding")
        add.tap()

        let registration = app.textFields["registration-field"]
        XCTAssertTrue(registration.waitForExistence(timeout: 8))
        registration.tap()
        registration.typeText("VH-UITEST")
        dismissKeyboard()

        openCatalogField("field-operator", title: "Airline / Operator")
        typeInCatalogSearch("QF")

        let ambiguous = app.staticTexts["Several operators share this code. Choose the specific one."]
        XCTAssertTrue(ambiguous.waitForExistence(timeout: 45), "QF did not stay ambiguous after the catalog loaded")
        let results = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'catalog-result-'"))
        XCTAssertGreaterThan(results.count, 1, "QF returned a single operator")
        XCTAssertFalse(app.buttons["confirm-selection"].isEnabled)

        let qantas = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'catalog-result-' AND label CONTAINS 'Qantas Airways'")
        ).firstMatch
        tapWhenHittable(qantas, name: "Qantas Airways")
        confirmSelection(returningTo: "Add Aircraft")

        openCatalogField("field-location", title: "Location / Airport")
        typeInCatalogSearch("Nearby park")
        let customLocation = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Use \"Nearby park\"'")).firstMatch
        tapWhenHittable(customLocation, name: "custom location")
        confirmSelection(returningTo: "Add Aircraft")

        tapWhenHittable(app.buttons["field-role"], name: "field-role")
        chooseClassification("classification-civil", label: "Civil")
        confirmSelection(returningTo: "Add Aircraft")

        tapWhenHittable(app.buttons["field-operation"], name: "field-operation")
        chooseClassification("classification-passenger", label: "Passenger")
        confirmSelection(returningTo: "Add Aircraft")

        let save = app.buttons["save-spotting"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertTrue(save.isEnabled)
        tapWhenHittable(save, name: "save-spotting")

        let card = app.buttons["spotting-card-VH-UITEST"]
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        tapWhenHittable(card, name: "saved card")
        assertSavedDetails(note: nil)

        tapWhenHittable(app.buttons["spotting-actions"], name: "spotting-actions")
        tapWhenHittable(app.buttons["Edit"], name: "Edit")
        let notes = app.textFields["notes-field"]
        tapWhenHittable(notes, name: "notes-field")
        notes.typeText("Ramp note")
        dismissKeyboard()
        tapWhenHittable(app.buttons["save-spotting"], name: "save edit")
        tapWhenHittable(app.buttons["Done"], name: "Done")

        app.terminate()
        app.launchArguments = ["-UITestSeedPhoto"]
        app.launch()
        XCTAssertTrue(card.waitForExistence(timeout: 15))
        tapWhenHittable(card, name: "reloaded card")
        assertSavedDetails(note: "Ramp note")
    }

    private func openCatalogField(_ identifier: String, title: String) {
        tapWhenHittable(app.buttons[identifier], name: identifier)
        let titleText = app.navigationBars[title]
        XCTAssertTrue(titleText.waitForExistence(timeout: 8), "Picker \(title) did not open\n\(app.debugDescription)")
    }

    private func typeInCatalogSearch(_ text: String) {
        let field = app.textFields["catalog-search"]
        XCTAssertTrue(field.waitForExistence(timeout: 8), "Missing catalog search\n\(app.debugDescription)")
        if field.isHittable {
            field.tap()
        }
        field.typeText(text)
        dismissKeyboard()
    }

    private func chooseClassification(_ identifier: String, label: String) {
        let option = app.buttons[identifier]
        XCTAssertTrue(option.waitForExistence(timeout: 8), "Missing \(label)\n\(app.debugDescription)")
        let confirm = app.buttons["confirm-selection"]
        var attempts = 0
        while !confirm.isEnabled && attempts < 3 {
            if option.isHittable {
                option.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5)).tap()
            } else if app.staticTexts[label].isHittable {
                app.staticTexts[label].tap()
            } else {
                option.tap()
            }
            attempts += 1
        }
        XCTAssertTrue(confirm.isEnabled, "Use stayed disabled after \(label)\n\(app.debugDescription)")
    }

    private func confirmSelection(returningTo title: String) {
        let confirm = app.buttons["confirm-selection"]
        tapWhenHittable(confirm, name: "confirm-selection")
        XCTAssertTrue(
            app.navigationBars[title].waitForExistence(timeout: 8),
            "Did not return to \(title)\n\(app.debugDescription)"
        )
    }

    /// Tap only after the control is on screen. `tap()` otherwise waits many minutes
    /// while it tries to scroll a covered or off-screen SwiftUI row into place.
    private func tapWhenHittable(_ element: XCUIElement, name: String) {
        XCTAssertTrue(element.waitForExistence(timeout: 8), "Missing \(name)\n\(app.debugDescription)")
        dismissKeyboard()
        var swipes = 0
        while !element.isHittable && swipes < 3 {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(element.isHittable, "\(name) is not on screen\n\(app.debugDescription)")
        element.tap()
    }

    private func assertSavedDetails(note: String?) {
        XCTAssertTrue(app.staticTexts["Qantas Airways"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Nearby park"].exists)
        XCTAssertTrue(app.staticTexts["Civil"].exists)
        XCTAssertTrue(app.staticTexts["Passenger"].exists)
        if let note {
            XCTAssertTrue(app.staticTexts[note].exists)
        }
    }

    private func dismissKeyboard() {
        guard app.keyboards.firstMatch.exists else { return }
        for label in ["return", "Return", "search", "Search", "done", "Done", "Go", "go"] {
            let button = app.keyboards.buttons[label]
            if button.exists && button.isHittable {
                button.tap()
                return
            }
            let key = app.keyboards.keys[label]
            if key.exists && key.isHittable {
                key.tap()
                return
            }
        }
        let bar = app.navigationBars.firstMatch
        if bar.exists {
            bar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)).tap()
        }
    }
}
