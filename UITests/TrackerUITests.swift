import XCTest

final class TrackerUITests: XCTestCase {
    @MainActor
    func testMapLibraryDetailsAndPlaces() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "-appearance", "light"]
        app.launch()
        let bag = app.buttons["tracker-row-fusion:demo-bag"]
        XCTAssertTrue(bag.waitForExistence(timeout: 20))
        capture("01-Objects")
        bag.tap()
        XCTAssertTrue(app.otherElements["tracker-detail-header"].waitForExistence(timeout: 10))
        capture("02-Tracker-Details")
        app.tabBars.buttons["Orte"].tap()
        XCTAssertTrue(app.staticTexts["Brandenburger Tor"].waitForExistence(timeout: 10))
        capture("03-Places")
    }

    @MainActor
    func testDarkAppearanceAndAccessibilityText() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "-appearance", "dark", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryXXXL"]
        app.launch()
        XCTAssertTrue(app.buttons["tracker-row-fusion:demo-bag"].waitForExistence(timeout: 20))
        capture("04-Dark-Large-Text")
    }

    @MainActor
    func testGroupsAndPollingSettings() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "-appearance", "light"]
        app.launch()
        XCTAssertTrue(app.buttons["tracker-row-fusion:demo-bag"].waitForExistence(timeout: 20))
        app.tabBars.buttons["Ich"].tap()
        app.buttons["Gruppen"].tap()
        XCTAssertTrue(app.staticTexts["Reisen"].waitForExistence(timeout: 10))
        capture("05-Groups")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["Serverzentrale"].tap()
        XCTAssertTrue(app.staticTexts["Ortungsnetzwerke"].waitForExistence(timeout: 10))
        capture("06-Server")
        app.buttons["Ortungsintervalle"].tap()
        XCTAssertTrue(app.staticTexts["Mindestens 30 Sekunden"].waitForExistence(timeout: 10))
        capture("07-Polling")
    }

    @MainActor
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
