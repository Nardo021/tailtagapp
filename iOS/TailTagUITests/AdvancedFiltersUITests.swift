import XCTest

final class AdvancedFiltersUITests: XCTestCase {
    private var app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-UITestReset", "-UITestSeedFilters"]
        app.launch()
    }

    func testSearchFiltersCombineAndPersistForTheSession() throws {
        let search = app.buttons["Search"]
        XCTAssertTrue(search.waitForExistence(timeout: 12), "Search tab did not appear")
        search.tap()

        openFilters()
        tapChoice("filter-choice-role-civil")
        tapChoice("filter-choice-operation-passenger")
        app.buttons["apply-filters"].tap()

        XCTAssertTrue(app.buttons["spotting-card-VH-QFA"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["spotting-card-VH-JST"].exists)
        XCTAssertFalse(app.buttons["spotting-card-VH-MIL"].exists)
        XCTAssertTrue(app.staticTexts["2 of 3 sightings"].waitForExistence(timeout: 3))

        openFilters()
        tapChoice("filter-choice-operator-catalog-op:qantas")
        tapChoice("filter-choice-operator-catalog-op:jetstar")
        app.buttons["apply-filters"].tap()
        XCTAssertTrue(app.buttons["spotting-card-VH-QFA"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["spotting-card-VH-JST"].exists)
        XCTAssertFalse(app.buttons["spotting-card-VH-MIL"].exists)

        app.buttons["filter-chip-operator-catalog-op:jetstar"].tap()
        XCTAssertTrue(app.buttons["spotting-card-VH-QFA"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["spotting-card-VH-JST"].exists)

        app.buttons["Recent"].tap()
        app.buttons["Search"].tap()
        XCTAssertTrue(app.buttons["filter-chip-operator-catalog-op:qantas"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["spotting-card-VH-QFA"].exists)
        XCTAssertFalse(app.buttons["spotting-card-VH-JST"].exists)

        app.buttons["clear-filters"].tap()
        XCTAssertTrue(app.buttons["spotting-card-VH-QFA"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["spotting-card-VH-JST"].exists)
        XCTAssertTrue(app.buttons["spotting-card-VH-MIL"].exists)
        XCTAssertTrue(app.staticTexts["3 sightings"].exists)

        app.buttons["sort-button"].tap()
        let registrationSort = app.buttons["Registration (A-Z)"]
        if registrationSort.waitForExistence(timeout: 3) {
            registrationSort.tap()
        } else {
            app.menuItems["Registration (A-Z)"].tap()
        }
        let cards = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'spotting-card-'"))
        XCTAssertEqual(cards.count, 3)
        XCTAssertEqual(cards.element(boundBy: 0).identifier, "spotting-card-VH-JST")
        XCTAssertEqual(cards.element(boundBy: 1).identifier, "spotting-card-VH-MIL")
        XCTAssertEqual(cards.element(boundBy: 2).identifier, "spotting-card-VH-QFA")
    }

    private func openFilters() {
        let filters = app.buttons["filters-button"]
        XCTAssertTrue(filters.waitForExistence(timeout: 8), "Filters button missing")
        filters.tap()
        XCTAssertTrue(app.buttons["apply-filters"].waitForExistence(timeout: 8), "Filter sheet did not open")
    }

    private func tapChoice(_ identifier: String) {
        let choice = app.buttons[identifier]
        XCTAssertTrue(choice.waitForExistence(timeout: 8), "Missing \(identifier)\n\(app.debugDescription)")
        var swipes = 0
        while !choice.isHittable && swipes < 8 {
            app.swipeUp()
            swipes += 1
        }
        choice.tap()
    }
}
