import XCTest

final class LoopCGMSetupUITests: XCTestCase {
    private let loopBundleIdentifier = "com.libre.loopkit3.Loop"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testMicroTechLinXSetupOpensFromSettings() throws {
        let app = XCUIApplication(bundleIdentifier: loopBundleIdentifier)
        app.launchArguments.append("-loop-ui-tests")
        app.launch()

        handleSystemAlerts(in: app)

        navigateToStatusScreenIfNeeded(in: app)
        tap(app.buttons["status.settings"], named: "Settings", in: app)
        assertSettingsScreenIsVisible(in: app)

        if openExistingMicroTechLinXIfConfigured(in: app) {
            assertMicroTechSettingsScreenIsVisible(in: app)
            return
        }

        tapAddCGM(in: app)
        tap(app.buttons["MicroTech LinX"], named: "MicroTech LinX", in: app)

        XCTAssertFalse(
            app.alerts["Unable to Open CGM"].waitForExistence(timeout: 2),
            "Selecting MicroTech LinX must not show Unable to Open CGM."
        )

        let setupTitle = app.staticTexts["microtech.setup.title"]
        let localizedSetupTitle = app.staticTexts["MicroTech LinX"]
        XCTAssertTrue(
            setupTitle.waitForExistence(timeout: 3) || localizedSetupTitle.waitForExistence(timeout: 7),
            "MicroTech LinX setup screen did not open."
        )

        let searchButton = app.buttons["microtech.setup.continue"]
        let localizedSearchButton = app.buttons["Search Nearby Devices"]
        XCTAssertTrue(
            searchButton.waitForExistence(timeout: 3) || localizedSearchButton.waitForExistence(timeout: 5),
            "MicroTech LinX nearby search button was not visible."
        )
    }

    private func openExistingMicroTechLinXIfConfigured(
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Bool {
        let currentCGM = app.buttons["settings.cgm.current"]
        guard currentCGM.waitForExistence(timeout: 2) else {
            return false
        }

        XCTAssertTrue(
            currentCGM.label.contains("MicroTech LinX"),
            "Current CGM is \(currentCGM.label), not MicroTech LinX.",
            file: file,
            line: line
        )
        currentCGM.tap()
        return true
    }

    private func assertMicroTechSettingsScreenIsVisible(
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertFalse(
            app.alerts["Unable to Open CGM"].waitForExistence(timeout: 2),
            "Opening configured MicroTech LinX must not show Unable to Open CGM.",
            file: file,
            line: line
        )

        let title = app.navigationBars["MicroTech LinX"]
        let deleteButton = app.buttons["Delete CGM"]
        XCTAssertTrue(
            title.waitForExistence(timeout: 5) || deleteButton.waitForExistence(timeout: 5),
            "Configured MicroTech LinX settings screen did not open.",
            file: file,
            line: line
        )
    }

    private func tap(
        _ element: XCUIElement,
        named name: String,
        in app: XCUIApplication,
        timeout: TimeInterval = 15,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        if !element.waitForExistence(timeout: timeout) {
            attachDiagnostics(in: app, named: name)
            XCTFail("\(name) was not visible.", file: file, line: line)
            return
        }
        element.tap()
    }

    private func assertSettingsScreenIsVisible(
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let addCGM = app.buttons["settings.cgm.add"]
        let currentCGM = app.buttons["settings.cgm.current"]
        let englishTitle = app.navigationBars["Settings"]
        let chineseTitle = app.navigationBars["设置"]
        XCTAssertTrue(
            addCGM.waitForExistence(timeout: 10) ||
                currentCGM.waitForExistence(timeout: 2) ||
                englishTitle.waitForExistence(timeout: 2) ||
                chineseTitle.waitForExistence(timeout: 2),
            "Settings screen was not visible.",
            file: file,
            line: line
        )
    }

    private func tapAddCGM(
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let addCGM = app.buttons["settings.cgm.add"]
        if !addCGM.waitForExistence(timeout: 10) {
            attachDiagnostics(in: app, named: "Add CGM")
            XCTFail("Add CGM was not visible. Remove the current CGM before running this add-flow test.", file: file, line: line)
            return
        }
        addCGM.tap()
    }

    private func navigateToStatusScreenIfNeeded(in app: XCUIApplication) {
        if app.buttons["status.settings"].waitForExistence(timeout: 3) {
            return
        }

        for _ in 0..<4 {
            if app.buttons["status.settings"].exists {
                return
            }

            let statusBackButton = app.navigationBars.buttons["Status"]
            let localizedStatusBackButton = app.navigationBars.buttons["状态"]
            if statusBackButton.exists {
                statusBackButton.tap()
            } else if localizedStatusBackButton.exists {
                localizedStatusBackButton.tap()
            } else {
                break
            }
        }
    }

    private func attachDiagnostics(in app: XCUIApplication, named name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "\(name) screen"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "\(name) accessibility hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
    }

    private func handleSystemAlerts(in app: XCUIApplication) {
        addUIInterruptionMonitor(withDescription: "System alert") { alert in
            for title in ["Allow", "OK", "Continue", "Not Now", "允许", "好", "继续", "以后", "稍后"] {
                let button = alert.buttons[title]
                if button.exists {
                    button.tap()
                    return true
                }
            }
            return false
        }
        app.tap()
    }
}
