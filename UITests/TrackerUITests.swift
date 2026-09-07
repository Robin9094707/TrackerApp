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
        let navigation = app.navigationBars["Objekte"]
        let initialY = navigation.frame.minY
        let handle = app.buttons["Sheet Grabber"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        handle.press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)))
        XCTAssertLessThan(navigation.frame.minY, initialY - 100)
        capture("08-Dark-Expanded")
        let expandedY = navigation.frame.minY
        let expandedHandle = app.buttons["Sheet Grabber"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        expandedHandle.press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55)))
        XCTAssertGreaterThan(navigation.frame.minY, expandedY + 100)
        capture("09-Dark-Collapsed")
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
        let server = app.buttons["Serverzentrale"]
        for _ in 0..<4 { if server.isHittable { break }; app.swipeUp() }
        server.tap()
        XCTAssertTrue(app.staticTexts["Ortungsnetzwerke"].waitForExistence(timeout: 10))
        capture("06-Server")
        app.buttons["Ortungsintervalle"].tap()
        XCTAssertTrue(app.staticTexts["Mindestens 30 Sekunden"].waitForExistence(timeout: 10))
        capture("07-Polling")
    }

    @MainActor
    func testAccountSecurityAndHistory() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "-appearance", "dark"]
        app.launch()
        let bag = app.buttons["tracker-row-fusion:demo-bag"]
        XCTAssertTrue(bag.waitForExistence(timeout: 20))
        bag.tap()
        app.buttons["tracker-history-link"].tap()
        XCTAssertTrue(app.buttons["Verlauf abspielen"].waitForExistence(timeout: 10))
        capture("10-History")
        app.tabBars.buttons["Ich"].tap()
        app.buttons["Konto & Sicherheit"].tap()
        XCTAssertTrue(app.buttons["Profil bearbeiten"].waitForExistence(timeout: 10))
        app.buttons["Passwort, 2FA & Passkeys"].tap()
        app.buttons["Zwei-Faktor-Schutz"].tap()
        XCTAssertTrue(app.staticTexts["Zwei-Faktor-Schutz nicht aktiv"].waitForExistence(timeout: 10))
        capture("11-Security")
    }

    @MainActor
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
