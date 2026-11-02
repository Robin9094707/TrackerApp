import XCTest

final class TrackerUITests: XCTestCase {
    @MainActor
    func testColdStartAndRelaunchWithoutSession() {
        let app = XCUIApplication()
        // Exercise production restoration, without the --ui-testing fixture shortcut.
        app.launchArguments = ["-appearance", "light", "-serverURL", ""] + ["-tracker.provider", "all", "-tracker.scope", "all"]
        for _ in 0..<2 {
            app.launch()
            XCTAssertTrue(app.buttons["local-google-launcher"].firstMatch.waitForExistence(timeout: 20))
            let terminated = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                app.state != .runningForeground
            }, object: nil)
            terminated.isInverted = true
            wait(for: [terminated], timeout: 6)
            XCTAssertEqual(app.state, .runningForeground)
            app.terminate()
        }
    }

    @MainActor
    func testMapLibraryDetailsAndPlaces() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "-appearance", "light"] + ["-tracker.provider", "all", "-tracker.scope", "all"]
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
        app.launchArguments = ["--ui-testing", "-appearance", "dark", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryXXXL"] + ["-tracker.provider", "all", "-tracker.scope", "all"]
        app.launch()
        XCTAssertTrue(app.buttons["tracker-row-fusion:demo-bag"].waitForExistence(timeout: 20))
        capture("04-Dark-Large-Text")
        let navigation = app.navigationBars["Objekte"]
        let initialY = navigation.frame.minY
        let handle = sheetGrabber(in: app).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        handle.press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)))
        XCTAssertLessThan(navigation.frame.minY, initialY - 100)
        capture("08-Dark-Expanded")
        let expandedY = navigation.frame.minY
        let expandedHandle = sheetGrabber(in: app).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        expandedHandle.press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55)))
        XCTAssertGreaterThan(navigation.frame.minY, expandedY + 100)
        capture("09-Dark-Collapsed")
    }

    @MainActor
    func testGroupsAndPollingSettings() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "-appearance", "light"] + ["-tracker.provider", "all", "-tracker.scope", "all"]
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
        app.launchArguments = ["--ui-testing", "-appearance", "dark"] + ["-tracker.provider", "all", "-tracker.scope", "all"]
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
    func testLocalGoogleCanOpenAndReturnToExistingTrackers() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "-appearance", "light"] + ["-tracker.provider", "all", "-tracker.scope", "all"]
        app.launch()
        let launcher = app.buttons["local-google-launcher"].firstMatch
        XCTAssertTrue(launcher.waitForExistence(timeout: 20))
        launcher.tap()
        let close = app.buttons["Zurück zu RJ Tracker"]
        XCTAssertTrue(close.waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["Bei Google anmelden"].waitForExistence(timeout: 10))
        capture("12-Native-Google-Account")
        close.tap()
        XCTAssertTrue(app.buttons["tracker-row-fusion:demo-bag"].waitForExistence(timeout: 10))
    }

    @MainActor
    func testLocalGoogleFallbackAndProviderScopedControls() {
        for provider in ["apple", "google", "all"] {
            let app = XCUIApplication()
            app.launchArguments = ["--ui-testing", "--ui-testing-local-google", "-native.localMode", "NO",
                "-tracker.provider", provider, "-serverURL", "https://offline.example.invalid"]
            app.launch()
            expandInspector(app)
            let expectedRow = provider == "apple" ? "tracker-row-apple:demo-keys" : "tracker-row-google:demo-local-tag"
            XCTAssertTrue(app.buttons[expectedRow].waitForExistence(timeout: 20))
            XCTAssertEqual(app.buttons["local-google-launcher"].firstMatch.exists, provider != "apple")
            app.tabBars.buttons["Ich"].tap()
            XCTAssertTrue(app.buttons["Mit Tracker-Server verbinden"].waitForExistence(timeout: 10))
            XCTAssertEqual(app.buttons["local-google-launcher"].firstMatch.exists, provider != "apple")
            capture("Local-Fallback-" + provider)
            app.terminate()
        }
    }

    @MainActor
    func testMotorolaFirmwareScreenRequiresOriginalAndHardwareBeforeInstall() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-local-google", "--ui-test-motorola",
            "-tracker.provider", "google", "-serverURL", "https://offline.example.invalid"]
        app.launch()
        expandInspector(app)
        let tag = app.buttons["tracker-row-google:demo-local-tag"]
        XCTAssertTrue(tag.waitForExistence(timeout: 20)); tag.tap()
        expandInspector(app)
        let firmware = app.buttons["motorola-firmware-link"]
        for _ in 0..<10 {
            if firmware.exists && firmware.isHittable { break }
            if app.collectionViews.firstMatch.exists { app.collectionViews.firstMatch.swipeUp() }
            else { app.swipeUp() }
        }
        XCTAssertTrue(firmware.exists); firmware.tap()
        XCTAssertTrue(app.staticTexts["motorola-firmware-hardware-limit"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["motorola-firmware-import"].exists)
        let install = app.buttons["motorola-firmware-install"]
        for _ in 0..<8 {
            if install.exists && install.isHittable { break }
            if app.collectionViews.firstMatch.exists { app.collectionViews.firstMatch.swipeUp() }
            else { app.swipeUp() }
        }
        XCTAssertTrue(install.exists); XCTAssertFalse(install.isEnabled)
        capture("Motorola-Firmware-Needs-Original-And-Hardware")
    }

    @MainActor
    func testGoogleIsAccessibleWhileServerRestoresAndUWBLabDoesNotPromiseRanging() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-local-google", "--ui-testing-restoring",
            "-native.localMode", "NO", "-tracker.provider", "google", "-serverURL", "https://offline.example.invalid"]
        app.launch()
        expandInspector(app)
        let tag = app.buttons["tracker-row-google:demo-local-tag"]
        XCTAssertTrue(tag.waitForExistence(timeout: 20))
        tag.tap()
        expandInspector(app)
        let lab = app.buttons["google-uwb-lab"]
        for _ in 0..<8 {
            if lab.exists && lab.isHittable { break }
            if app.collectionViews.firstMatch.exists { app.collectionViews.firstMatch.swipeUp() }
            else { app.swipeUp() }
        }
        XCTAssertTrue(lab.exists)
        lab.tap()
        XCTAssertTrue(app.staticTexts["uwb-compatibility-status"].waitForExistence(timeout: 10))
        let probe = app.buttons["Fähigkeiten des Trackers prüfen"]
        for _ in 0..<4 {
            if probe.exists { break }
            if app.collectionViews.firstMatch.exists { app.collectionViews.firstMatch.swipeUp() }
            else { app.swipeUp() }
        }
        XCTAssertTrue(probe.exists)
        XCTAssertFalse(probe.isEnabled)
        capture("UWB-Lab-No-Fabricated-Ranging")
    }

    @MainActor
    func testGoogleDetailsUseOneTitleAndDirectRefresh() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-local-google", "-tracker.provider", "google", "-AppleLanguages", "(en)"]
        app.launch()
        expandInspector(app)
        let tag = app.buttons["tracker-row-google:demo-local-tag"]
        XCTAssertTrue(tag.waitForExistence(timeout: 20)); tag.tap()
        expandInspector(app)
        XCTAssertTrue(app.buttons["google-refresh-location"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["google-locate-tile"].exists)
        XCTAssertEqual(app.navigationBars.staticTexts.matching(identifier: "Lokaler Test-Tracker").count, 1)
        XCTAssertFalse(app.otherElements["tracker-detail-header"].staticTexts["Lokaler Test-Tracker"].exists)
        XCTAssertFalse(app.staticTexts["1h"].exists)
        capture("Google-Compact-German-Details")
    }

    @MainActor
    func testGoogleRouteUsesSavedServerLocationAndOfflineStatusOffersRetry() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-local-google", "--ui-testing-google-server-fallback",
            "-tracker.provider", "google", "-tracker.scope", "all", "-serverURL", "https://offline.example.invalid"]
        app.launch()
        expandInspector(app)
        let retry = app.buttons["sync-server-retry"]
        let library = app.collectionViews.firstMatch
        // List creates rows lazily; the status footer can sit below the first
        // viewport even after expanding the inspector (especially at large text).
        for _ in 0..<6 {
            if retry.exists && retry.isHittable { break }
            if library.exists { library.swipeUp() } else { app.swipeUp() }
        }
        XCTAssertTrue(retry.waitForExistence(timeout: 10))
        XCTAssertTrue(retry.isEnabled)
        XCTAssertTrue(app.staticTexts["Server nicht verbunden"].exists)
        let tag = app.buttons["tracker-row-google:demo-local-tag"]
        for _ in 0..<6 {
            if tag.exists && tag.isHittable { break }
            if library.exists { library.swipeDown() } else { app.swipeDown() }
        }
        XCTAssertTrue(tag.waitForExistence(timeout: 10))
        tag.tap()
        expandInspector(app)
        let route = app.buttons["google-route-tile"]
        XCTAssertTrue(route.waitForExistence(timeout: 10))
        XCTAssertTrue(route.isEnabled, "A saved server location must remain routable when Google has no local location yet.")
        XCTAssertTrue(app.buttons["google-locate-tile"].exists)
        capture("Google-Saved-Location-Route")
    }

    @MainActor
    private func sheetGrabber(in app: XCUIApplication) -> XCUIElement {
        // UIKit localizes this system control when the app declares German.
        app.buttons.matching(NSPredicate(format: "label == %@ OR label == %@", "Sheet Grabber", "Aufzeichnungsblatt")).firstMatch
    }

    @MainActor
    private func expandInspector(_ app: XCUIApplication) {
        let grabber = sheetGrabber(in: app).firstMatch
        if grabber.waitForExistence(timeout: 10) {
            grabber.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.10)))
        }
    }

    @MainActor
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

