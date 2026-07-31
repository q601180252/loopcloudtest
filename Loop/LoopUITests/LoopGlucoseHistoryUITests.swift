//
//  LoopGlucoseHistoryUITests.swift
//  LoopUITests
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import XCTest

final class LoopGlucoseHistoryUITests: XCTestCase {
    private let loopBundleIdentifier = "com.libre.loopkit3.Loop"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testConfiguredCGMOpensGlucoseHistoryAndSwitchesRanges() {
        let app = XCUIApplication(bundleIdentifier: loopBundleIdentifier)
        app.launchArguments.append("-loop-ui-tests")
        app.launch()

        handleSystemAlerts(in: app)
        navigateToStatusScreenIfNeeded(in: app)

        let historyEntry = app.cells["status.glucoseHistory"]
        tap(historyEntry, named: "Glucose History entry", in: app)

        let historyNavigationBar = app.navigationBars["Glucose History"]
        XCTAssertTrue(
            historyNavigationBar.waitForExistence(timeout: 15),
            "Glucose History screen did not open."
        )

        let rangePicker = app.segmentedControls["glucoseHistory.range"]
        XCTAssertTrue(
            rangePicker.waitForExistence(timeout: 15),
            "Glucose History range picker was not visible."
        )
        XCTAssertTrue(
            app.otherElements["glucoseHistory.chart"].waitForExistence(timeout: 15),
            "Glucose History chart was not visible."
        )

        assertSelectedRange("6 Hours", in: rangePicker)
        selectRange("12 Hours", in: rangePicker)
        assertSelectedRange("12 Hours", in: rangePicker)
        selectRange("24 Hours", in: rangePicker)
        assertSelectedRange("24 Hours", in: rangePicker)

        waitForSuccessfulTerminalState(in: app)

        let backButton = historyNavigationBar.buttons.firstMatch
        tap(backButton, named: "Glucose History back button", in: app)
        XCTAssertTrue(
            historyEntry.waitForExistence(timeout: 15),
            "Status screen did not return after leaving Glucose History."
        )
    }

    private func selectRange(
        _ title: String,
        in rangePicker: XCUIElement,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let button = rangePicker.buttons[title]
        XCTAssertTrue(
            button.waitForExistence(timeout: 5),
            "\(title) range was not visible.",
            file: file,
            line: line
        )
        button.tap()
    }

    private func assertSelectedRange(
        _ title: String,
        in rangePicker: XCUIElement,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let button = rangePicker.buttons[title]
        XCTAssertTrue(
            button.waitForExistence(timeout: 5),
            "\(title) range was not visible.",
            file: file,
            line: line
        )
        XCTAssertTrue(
            button.isSelected,
            "\(title) range was not selected.",
            file: file,
            line: line
        )
    }

    private func waitForSuccessfulTerminalState(
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let historyList = app.otherElements["glucoseHistory.list"]
        let emptyState = app.staticTexts["glucoseHistory.empty"]
        let errorState = app.otherElements["glucoseHistory.error"]
        let terminalStateReached = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                historyList.exists || emptyState.exists || errorState.exists
            },
            object: app
        )

        guard XCTWaiter.wait(for: [terminalStateReached], timeout: 15) == .completed else {
            attachDiagnostics(in: app, named: "Glucose History 24-hour terminal state")
            XCTFail(
                "The 24-hour Glucose History request did not finish.",
                file: file,
                line: line
            )
            return
        }

        if errorState.exists {
            attachDiagnostics(in: app, named: "Glucose History 24-hour error state")
            XCTFail(
                "The 24-hour Glucose History request finished with an error.",
                file: file,
                line: line
            )
            return
        }

        XCTAssertTrue(
            historyList.exists || emptyState.exists,
            "The 24-hour Glucose History request did not show readings or an empty state.",
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
