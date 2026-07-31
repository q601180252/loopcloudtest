import CoreBluetooth
import HealthKit
import LoopKit
import LoopKitUI
import XCTest
@testable import MicroTechCGM
@testable import MicroTechCGMUI

final class MicroTechBroadcastModeTests: XCTestCase {
    func testBroadcastModeScanUsesBroadcastPath() {
        var state = MicroTechCGMManagerState()
        state.connectionMode = .broadcast
        let bluetoothManager = BroadcastFakeMicroTechBluetoothManager()
        let manager = MicroTechCGMManager(
            state: state,
            bluetoothManagerFactory: { bluetoothManager }
        )

        XCTAssertTrue(manager.scanForSensor())

        XCTAssertEqual(bluetoothManager.configuredModes, [.broadcast])
        XCTAssertEqual(bluetoothManager.broadcastScanRemoteIdentifiers, [nil])
        XCTAssertTrue(bluetoothManager.scanRemoteIdentifiers.isEmpty)
        XCTAssertEqual(bluetoothManager.refreshConnectedPeripheralCallCount, 0)
    }

    func testDirectModeScanKeepsDirectPath() {
        var state = MicroTechCGMManagerState()
        state.connectionMode = .direct
        let remoteIdentifier = UUID()
        state.remoteIdentifier = remoteIdentifier
        let bluetoothManager = BroadcastFakeMicroTechBluetoothManager()
        let manager = MicroTechCGMManager(
            state: state,
            bluetoothManagerFactory: { bluetoothManager }
        )

        XCTAssertTrue(manager.scanForSensor())

        XCTAssertEqual(bluetoothManager.configuredModes, [.direct])
        XCTAssertEqual(bluetoothManager.scanRemoteIdentifiers, [remoteIdentifier])
        XCTAssertTrue(bluetoothManager.broadcastScanRemoteIdentifiers.isEmpty)
    }

    func testBroadcastAdvertisementStoresLatestReading() throws {
        var state = MicroTechCGMManagerState()
        state.connectionMode = .broadcast
        let remoteIdentifier = UUID()
        let discoveredAt = Date(timeIntervalSince1970: 1_800_000_000)
        let manager = MicroTechCGMManager(state: state)

        let sample = try manager.acceptBroadcastAdvertisement(advertisement(
            identifier: remoteIdentifier,
            localName: "AiDEX X-222227JKFK",
            discoveredAt: discoveredAt
        ))

        XCTAssertNotNil(sample)
        XCTAssertEqual(manager.state.connectionMode, .broadcast)
        XCTAssertEqual(manager.state.remoteIdentifier, remoteIdentifier)
        XCTAssertEqual(manager.state.deviceName, "AiDEX X-222227JKFK")
        XCTAssertEqual(manager.state.sensorSerial, "222227JKFK")
        XCTAssertEqual(manager.state.lastReadingDate, discoveredAt)
        XCTAssertEqual(manager.state.latestSampleNumber, 21600)
        XCTAssertEqual(manager.state.latestReading?.glucoseMgdl, 110)
        XCTAssertEqual(manager.state.latestReading?.quality, 67)
        XCTAssertTrue(manager.state.hasConnectedSensorSession)
    }

    func testBroadcastDuplicateAdvertisementIsIgnored() throws {
        var state = MicroTechCGMManagerState()
        state.connectionMode = .broadcast
        let manager = MicroTechCGMManager(state: state)
        let firstAdvertisement = advertisement(localName: "AiDEX X-222227JKFK")

        XCTAssertNotNil(try manager.acceptBroadcastAdvertisement(firstAdvertisement))
        XCTAssertNil(try manager.acceptBroadcastAdvertisement(firstAdvertisement))
        XCTAssertEqual(manager.state.latestSampleNumber, 21600)
    }

    func testBroadcastAdvertisementLogsParsedAndAcceptedEvents() throws {
        var state = MicroTechCGMManagerState()
        state.connectionMode = .broadcast
        let manager = MicroTechCGMManager(state: state)
        var loggedEvents: [(type: DeviceLogEntryType, message: String)] = []
        manager.onboardingDeviceLogHandler = { _, type, message in
            loggedEvents.append((type: type, message: message))
        }

        _ = try manager.acceptBroadcastAdvertisement(advertisement(
            identifier: UUID(uuidString: "00000000-0000-0000-0000-000000000123")!,
            localName: "AiDEX X-222227JKFK",
            discoveredAt: Date(timeIntervalSince1970: 1_800_000_000)
        ))

        let parsedLog = try XCTUnwrap(loggedEvents.first { event in
            event.type == .receive && event.message.contains("stage=broadcast event=parsed")
        })
        XCTAssertTrue(parsedLog.message.contains("identifier=00000000-0000-0000-0000-000000000123"))
        XCTAssertTrue(parsedLog.message.contains("serial=222227JKFK"))
        XCTAssertTrue(parsedLog.message.contains("sample=21600"))
        XCTAssertTrue(parsedLog.message.contains("value=110"))
        XCTAssertTrue(parsedLog.message.contains("trend=2"))
        XCTAssertTrue(parsedLog.message.contains("status=1"))
        XCTAssertTrue(parsedLog.message.contains("records=3"))
        XCTAssertTrue(parsedLog.message.contains("rssi=-60"))
        XCTAssertTrue(parsedLog.message.contains("rawHex=60540100026E80436C80416A80410000F33EE04E"))

        let acceptedLog = try XCTUnwrap(loggedEvents.first { event in
            event.type == .receive && event.message.contains("stage=broadcast event=accepted")
        })
        XCTAssertTrue(acceptedLog.message.contains("identifier=00000000-0000-0000-0000-000000000123"))
        XCTAssertTrue(acceptedLog.message.contains("serial=222227JKFK"))
        XCTAssertTrue(acceptedLog.message.contains("sample=21600"))
        XCTAssertTrue(acceptedLog.message.contains("value=110"))
        XCTAssertTrue(acceptedLog.message.contains("trend=2"))
        XCTAssertTrue(acceptedLog.message.contains("status=1"))
        XCTAssertTrue(acceptedLog.message.contains("records=3"))
        XCTAssertTrue(acceptedLog.message.contains("rawHex=60540100026E80436C80416A80410000F33EE04E"))
    }

    func testBroadcastParseErrorLogNamesPeripheralAndAdvertisement() throws {
        var state = MicroTechCGMManagerState()
        state.connectionMode = .broadcast
        let manager = MicroTechCGMManager(state: state)
        var loggedEvents: [(type: DeviceLogEntryType, message: String)] = []
        manager.onboardingDeviceLogHandler = { _, type, message in
            loggedEvents.append((type: type, message: message))
        }

        manager.logBroadcastParseError(
            MicroTechAidexBroadcastParserError.missingManufacturerData,
            advertisement: MicroTechBroadcastAdvertisement(
                identifier: UUID(uuidString: "00000000-0000-0000-0000-000000000124")!,
                localName: "AiDEX X-222227JKFK",
                peripheralName: "AiDEX Peripheral",
                advertisementData: [:],
                rssi: -71,
                discoveredAt: Date(timeIntervalSince1970: 1_800_000_000)
            )
        )

        let rejectedLog = try XCTUnwrap(loggedEvents.first { event in
            event.type == .receive && event.message.contains("stage=broadcast event=rejected reason=parseError")
        })
        XCTAssertTrue(rejectedLog.message.contains("identifier=00000000-0000-0000-0000-000000000124"))
        XCTAssertTrue(rejectedLog.message.contains("name=AiDEX X-222227JKFK"))
        XCTAssertTrue(rejectedLog.message.contains("rssi=-71"))
        XCTAssertTrue(rejectedLog.message.contains("advertisement=nil"))
    }

    func testBroadcastModeSettingsDisplayString() {
        var state = MicroTechCGMManagerState()
        state.connectionMode = .broadcast
        let manager = MicroTechCGMManager(state: state)
        let viewModel = MicroTechSettingsViewModel(
            cgmManager: manager,
            displayGlucosePreference: DisplayGlucosePreference(displayGlucoseUnit: Self.mgdlUnit)
        )

        XCTAssertEqual(viewModel.dataModeDescription, "Broadcast Data")
    }

    private func advertisement(
        identifier: UUID = UUID(),
        localName: String?,
        discoveredAt: Date = Date(timeIntervalSince1970: 1_800_000_000)
    ) -> MicroTechBroadcastAdvertisement {
        MicroTechBroadcastAdvertisement(
            identifier: identifier,
            localName: localName,
            peripheralName: nil as String?,
            advertisementData: [
                CBAdvertisementDataManufacturerDataKey: try! Data(microTechHexadecimalString: "590060540100026e80436c80416a80410000f33ee04e"),
            ],
            rssi: -60,
            discoveredAt: discoveredAt
        )
    }

    private static let mgdlUnit = HKUnit
        .gramUnit(with: .milli)
        .unitDivided(by: .literUnit(with: .deci))
}

private final class BroadcastFakeMicroTechBluetoothManager: MicroTechBluetoothManaging {
    weak var delegate: MicroTechBluetoothManagerDelegate?
    var logHandler: ((String, MicroTechBluetoothLogType) -> Void)?
    var isScanning = false
    var isConnected = false
    private(set) var configuredModes: [MicroTechCGMConnectionMode] = []
    private(set) var scanRemoteIdentifiers: [UUID?] = []
    private(set) var broadcastScanRemoteIdentifiers: [UUID?] = []
    private(set) var refreshConnectedPeripheralCallCount = 0
    private(set) var disconnectCallCount = 0
    private(set) var forgetPeripheralCallCount = 0

    func configureConnectionMode(_ mode: MicroTechCGMConnectionMode) {
        configuredModes.append(mode)
    }

    func scan(remoteIdentifier: UUID?) {
        isScanning = true
        scanRemoteIdentifiers.append(remoteIdentifier)
    }

    func scanForBroadcast(remoteIdentifier: UUID?) {
        isScanning = true
        broadcastScanRemoteIdentifiers.append(remoteIdentifier)
    }

    func refreshConnectedPeripheral() {
        refreshConnectedPeripheralCallCount += 1
    }

    func disconnect() {
        disconnectCallCount += 1
        isScanning = false
        isConnected = false
    }

    func forgetPeripheral() {
        forgetPeripheralCallCount += 1
    }
}
