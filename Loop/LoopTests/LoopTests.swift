//
//  LoopTests.swift
//  LoopTests
//
//  Created by Darin Krauss on 9/18/19.
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

import XCTest
import HealthKit
import LoopKit
import LoopKitUI

@testable import Loop

class LoopTests: XCTestCase {
    func testDeviceDataManagerDidBecomeActiveRefreshesCGM() {
        var events: [String] = []

        DeviceDataManager.handleDidBecomeActive(
            updatePumpManagerBLEHeartbeatPreference: {
                events.append("heartbeat")
            },
            refreshCGM: {
                events.append("refreshCGM")
            }
        )

        XCTAssertEqual(events, ["heartbeat", "refreshCGM"])
    }

    func testDeviceDataManagerCGMStoreLogMessageIncludesManagerIdentifierAndSampleIds() {
        let sampleDate = Date(timeIntervalSince1970: 1_700_000_000)
        let sample = NewGlucoseSample(
            date: sampleDate,
            quantity: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 95),
            condition: nil,
            trend: nil,
            trendRate: nil,
            isDisplayOnly: false,
            wasUserEntered: false,
            syncIdentifier: "ABC123-21600",
            device: HKDevice(
                name: nil,
                manufacturer: "MicroTech Medical",
                model: "LinX",
                hardwareVersion: nil,
                firmwareVersion: nil,
                softwareVersion: nil,
                localIdentifier: nil,
                udiDeviceIdentifier: nil
            )
        )

        let message = DeviceDataManager.cgmGlucoseStoreCompletedLogMessage(
            managerIdentifier: "MicroTechLinXCGMManager",
            requestedSamples: [sample],
            storedCount: 1
        )

        XCTAssertTrue(message.contains("manager=MicroTechLinXCGMManager"))
        XCTAssertTrue(message.contains("requested=1"))
        XCTAssertTrue(message.contains("stored=1"))
        XCTAssertTrue(message.contains("ids=[ABC123-21600]"))
        XCTAssertTrue(message.contains("valuesMgdl=[95]"))
    }

    func testConfigureCGMOnboardingDeviceLoggingExportsLinXScanFailure() throws {
        let storageDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: storageDirectory)
        }
        let export = autoreleasepool {
            let storageFile = storageDirectory.appendingPathComponent("DeviceLog.sqlite")
            let deviceLog = PersistentDeviceLog(storageFile: storageFile)
            let controller = FakeCGMOnboardingLoggingController()
            DeviceDataManager.configureCGMOnboardingDeviceLogging(on: controller, deviceLog: deviceLog)
            let saved = expectation(description: "LinX scan failure saved")

            controller.onboardingDeviceLogHandler?(
                "MicroTechLinXCGMManager",
                "22222DKCZE",
                .error,
                "stage=scan event=failed reason=timeout"
            )
            deviceLog.getLogEntries(startDate: .distantPast) { result in
                if case .failure(let error) = result {
                    XCTFail(String(describing: error))
                }
                saved.fulfill()
            }
            wait(for: [saved], timeout: 2)

            let stream = TestDataOutputStream()
            let progress = Progress(totalUnitCount: 1)
            XCTAssertNil(deviceLog.export(startDate: .distantPast, endDate: .distantFuture, to: stream, progress: progress))
            return (name: deviceLog.exportName, data: stream.data)
        }
        let exportedEntries = try JSONDecoder().decode([ExportedDeviceLogEntry].self, from: export.data)
        let matchingEntries = exportedEntries.filter {
            $0.managerIdentifier == "MicroTechLinXCGMManager" &&
                $0.deviceIdentifier == "22222DKCZE" &&
                $0.type == "error" &&
                $0.message == "stage=scan event=failed reason=timeout"
        }

        XCTAssertEqual(export.name, "DeviceLog.json")
        XCTAssertEqual(matchingEntries.count, 1)
        XCTAssertEqual(exportedEntries.count, 1)
        XCTAssertEqual(matchingEntries.first?.message, "stage=scan event=failed reason=timeout")
    }

    func testPresentAfterDismissingPresentedViewControllerDismissesBeforePresenting() {
        let root = MockPresentationViewController()
        let presented = UIViewController()
        let destination = UIViewController()
        root.fakePresentedViewController = presented

        root.presentAfterDismissingPresentedViewController(destination)

        XCTAssertTrue(root.didDismissPresentedViewController)
        XCTAssertTrue(root.presentedDestinationViewController === destination)
    }

    func testPresentAfterDismissingPresentedViewControllerDismissesAncestorPresentationBeforePresenting() {
        let root = MockPresentationViewController()
        let navigationController = MockNavigationController(rootViewController: root)
        let presented = UIViewController()
        let destination = UIViewController()
        navigationController.fakePresentedViewController = presented

        root.presentAfterDismissingPresentedViewController(destination)

        XCTAssertTrue(navigationController.didDismissPresentedViewController)
        XCTAssertTrue(root.presentedDestinationViewController === destination)
    }
}

private final class MockPresentationViewController: UIViewController {
    var fakePresentedViewController: UIViewController?
    var didDismissPresentedViewController = false
    var presentedDestinationViewController: UIViewController?

    override var presentedViewController: UIViewController? {
        fakePresentedViewController
    }

    override func dismiss(animated flag: Bool, completion: (() -> Void)? = nil) {
        didDismissPresentedViewController = true
        fakePresentedViewController = nil
        completion?()
    }

    override func present(_ viewControllerToPresent: UIViewController, animated flag: Bool, completion: (() -> Void)? = nil) {
        presentedDestinationViewController = viewControllerToPresent
        completion?()
    }
}

private final class MockNavigationController: UINavigationController {
    var fakePresentedViewController: UIViewController?
    var didDismissPresentedViewController = false

    override var presentedViewController: UIViewController? {
        fakePresentedViewController
    }

    override func dismiss(animated flag: Bool, completion: (() -> Void)? = nil) {
        didDismissPresentedViewController = true
        fakePresentedViewController = nil
        completion?()
    }
}

private final class FakeCGMOnboardingLoggingController: UIViewController, CGMManagerOnboarding, CGMManagerOnboardingDeviceLogging {
    var cgmManagerOnboardingDelegate: CGMManagerOnboardingDelegate?
    var onboardingDeviceLogHandler: CGMManagerOnboardingDeviceLogHandler?
}

private final class TestDataOutputStream: DataOutputStream {
    private(set) var data = Data()
    var streamError: Error?

    func write(_ data: Data) throws {
        self.data.append(data)
    }

    func finish(sync: Bool) throws {}
}

private struct ExportedDeviceLogEntry: Decodable {
    let managerIdentifier: String
    let deviceIdentifier: String?
    let type: String
    let message: String
}

extension XCTestCase {
    
    func waitOnMain(timeout: TimeInterval = 1.0, file: StaticString = #file, function: String = #function, line: UInt = #line) {
        let exp = expectation(description: function)
        var fulfilled = false
        DispatchQueue.main.async {
            fulfilled = true
            exp.fulfill()
        }
        wait(for: [exp], timeout: timeout)
        XCTAssertTrue(fulfilled, "Failed to wait on main in \(function)", file: file, line: line)
    }

}
