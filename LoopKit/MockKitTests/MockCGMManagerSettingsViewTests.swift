//
//  MockCGMManagerSettingsViewTests.swift
//  MockKitTests
//

import XCTest

final class MockCGMManagerSettingsViewTests: XCTestCase {
    func testCGMSimulatorSettingsDeclaresDeleteCGMAction() throws {
        let source = try String(contentsOf: settingsViewSourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("deleteCGMSection"))
        XCTAssertTrue(source.contains("Button(action: { presentedAlert = .deleteCGM })"))
        XCTAssertTrue(source.contains("Text(\"Delete CGM\")"))
        XCTAssertTrue(source.contains("Text(\"Are you sure you want to delete this CGM?\")"))
        XCTAssertTrue(source.contains("viewModel.cgmManager.delete"))
    }

    func testCGMSimulatorIsNotDeclaredAsUserSelectableStaticCGM() throws {
        let source = try String(contentsOf: loopCGMManagerSourceURL, encoding: .utf8)

        XCTAssertFalse(source.contains("CGMManagerDescriptor(identifier: MockCGMManager.pluginIdentifier"))
    }

    private var settingsViewSourceURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("MockKitUI/Views/MockCGMManagerSettingsView.swift")
    }

    private var loopCGMManagerSourceURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Loop/Loop/Managers/CGMManager.swift")
    }
}
