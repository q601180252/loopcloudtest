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

        let setupInput = app.textFields["microtech.setup.deviceNameOrSerial"]
        let localizedSetupInput = app.textFields["AiDEX-222227HAUZ or sensor serial"]
        XCTAssertTrue(
            setupInput.waitForExistence(timeout: 3) || localizedSetupInput.waitForExistence(timeout: 5),
            "MicroTech LinX setup input was not visible."
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
