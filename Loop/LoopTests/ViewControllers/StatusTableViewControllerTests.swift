//
//  StatusTableViewControllerTests.swift
//  LoopTests
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import XCTest
@testable import Loop

final class StatusTableViewControllerTests: XCTestCase {
    func testGlucoseHistoryEntryIsHiddenWithoutConfiguredCGM() {
        XCTAssertFalse(
            StatusTableViewController.shouldShowGlucoseHistoryEntry(hasConfiguredCGM: false)
        )
    }

    func testGlucoseHistoryEntryIsShownWithAnyConfiguredCGM() {
        XCTAssertTrue(
            StatusTableViewController.shouldShowGlucoseHistoryEntry(hasConfiguredCGM: true)
        )
    }
}
