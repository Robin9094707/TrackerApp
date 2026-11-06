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
        let school = app.buttons["tracker-school-plan"]
        XCTAssertTrue(school.waitForExistence(timeout: 10))
        school.tap()
        let edit = app.buttons["Schultaschenmodus einrichten"]
        XCTAssertTrue(edit.waitForExistence(timeout: 10))
        edit.tap()
        let enabled = app.switches["school-plan-enabled"]
        XCTAssertTrue(enabled.waitForExistence(timeout: 10))
        XCTAssertTrue(enabled.isHittable)
        enabled.coordinate(withNormalizedOffset: CGVector(dx: 0.80, dy: 0.5)).tap()
        let switchedOn = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "1"), object: enabled)
        wait(for: [switchedOn], timeout: 5)
        let addPlace = app.buttons["Ort hinzufügen"]
        for _ in 0..<5 where !addPlace.isHittable { app.swipeUp() }
        XCTAssertTrue(addPlace.exists)
        app.buttons["Abbrechen"].tap()
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
        XCTAssertTrue(app.staticTexts["Alles im Blick."].exists)
        app.buttons["tracker-row-fusion:demo-bag"].tap()
        XCTAssertTrue(app.otherElements["tracker-detail-header"].waitForExistence(timeout: 10))
        capture("08-Dark-Large-Detail")
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
        let today = app.buttons["history-today"]
        XCTAssertTrue(today.waitForExistence(timeout: 10))
        today.tap()
        let fit = app.buttons["history-map-fit"]
        XCTAssertTrue(fit.waitForExistence(timeout: 10))
        fit.tap()
        fit.tap()
        app.buttons["history-map-expand"].tap()
        let close = app.buttons["history-map-close"]
        XCTAssertTrue(close.waitForExistence(timeout: 10))
        app.buttons["history-map-full-fit"].tap()
        close.tap()
        XCTAssertTrue(fit.waitForExistence(timeout: 10))

        let stays = app.buttons["Aufenthalte"].firstMatch
        for _ in 0..<3 where !stays.isHittable {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.025, dy: 0.77))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.025, dy: 0.34)))
        }
        XCTAssertTrue(stays.isHittable)
        stays.tap()
        let stay = app.buttons["history-stay-0"]
        XCTAssertTrue(stay.waitForExistence(timeout: 10))
        if !stay.isHittable {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.025, dy: 0.77))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.025, dy: 0.47)))
        }
        XCTAssertTrue(stay.isHittable)
        stay.tap()
        XCTAssertTrue(close.waitForExistence(timeout: 10))
        close.tap()
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
    func testPanelDashboardMapAndBarkSettings() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "-appearance", "light", "-tracker.provider", "all", "-tracker.scope", "all"]
        app.launch()
        XCTAssertTrue(app.buttons["tracker-row-fusion:demo-bag"].waitForExistence(timeout: 20))
        capture("Panel-Dashboard")
        app.buttons["Karte"].firstMatch.tap()
        XCTAssertTrue(app.buttons["dashboard-map-fit"].waitForExistence(timeout: 10))
        app.buttons["dashboard-map-fit"].tap()
        capture("Panel-Map")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["Bark"].firstMatch.tap()
        XCTAssertTrue(app.switches["Bark aktiv"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.textFields["Bark-Server"].exists)
        capture("Panel-Bark")
    }

    @MainActor
    private func sheetGrabber(in app: XCUIApplication) -> XCUIElement {
        // UIKit localizes this system control when the app declares German.
        app.buttons.matching(NSPredicate(format: "label == %@ OR label == %@", "Sheet Grabber", "Aufzeichnungsblatt")).firstMatch
    }

    @MainActor
    private func expandInspector(_ app: XCUIApplication) {
        // The panel dashboard uses the full navigation area; no sheet expansion required.
        XCTAssertTrue(app.tabBars.firstMatch.exists)
    }

    @MainActor
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

