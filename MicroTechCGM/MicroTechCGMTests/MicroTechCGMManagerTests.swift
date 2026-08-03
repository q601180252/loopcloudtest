import CoreBluetooth
import HealthKit
import LoopKit
import LoopKitUI
import SwiftUI
import XCTest
@testable import MicroTechCGM
@testable import MicroTechCGMUI

final class MicroTechCGMManagerTests: XCTestCase {
    func testMicroTechDoesNotDisablePumpBLEHeartbeat() {
        let manager = MicroTechCGMManager()

        XCTAssertFalse(manager.providesBLEHeartbeat)
    }

    func testPluginReturnsMicroTechCGMManagerType() {
        let pluginBundle = microTechPluginBundle()
        do {
            try pluginBundle.loadAndReturnError()
        } catch {
            return XCTFail(String(describing: error))
        }
        guard let pluginClass = pluginBundle.principalClass as? NSObject.Type else {
            return XCTFail("Expected MicroTechCGMPlugin principal class")
        }
        guard let plugin = pluginClass.init() as? CGMManagerUIPlugin else {
            return XCTFail("Expected MicroTechCGMPlugin to conform to CGMManagerUIPlugin")
        }

        XCTAssertTrue(plugin.cgmManagerType == MicroTechCGMManager.self)
    }

    func testPluginInfoPlistContainsLoopMetadata() {
        let pluginBundle = microTechPluginBundle()

        XCTAssertEqual(pluginBundle.infoDictionary?["NSPrincipalClass"] as? String, "MicroTechCGMPlugin")
        XCTAssertEqual(pluginBundle.infoDictionary?["com.loopkit.Loop.CGMManagerDisplayName"] as? String, "MicroTech LinX")
        XCTAssertEqual(pluginBundle.infoDictionary?["com.loopkit.Loop.CGMManagerIdentifier"] as? String, "MicroTechLinXCGMManager")
    }

    func testMakeSampleConvertsReadingForLoop() {
        let manager = MicroTechCGMManager()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let reading = makeReading(sampleNumber: 42, glucoseMgdl: 123, receivedAt: date)

        let sample = manager.makeSample(from: reading)

        XCTAssertEqual(sample.quantity.doubleValue(for: Self.mgdlUnit), 123, accuracy: 0.001)
        XCTAssertEqual(sample.date, date)
        XCTAssertEqual(sample.syncIdentifier, "ABC123-42")
        XCTAssertEqual(sample.device?.manufacturer, "MicroTech Medical")
        XCTAssertEqual(sample.device?.model, "LinX")
        XCTAssertEqual(sample.trend, GlucoseTrend.down)
        XCTAssertEqual(sample.isDisplayOnly, false)
        XCTAssertEqual(sample.wasUserEntered, false)
    }

    func testAcceptReturnsSampleForFirstValidReadingAndNilForDuplicateSampleNumber() {
        let manager = MicroTechCGMManager()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let reading = makeReading(sampleNumber: 42, glucoseMgdl: 123, receivedAt: date)

        let firstSample = manager.accept(reading)
        let duplicateSample = manager.accept(reading)

        XCTAssertEqual(firstSample?.syncIdentifier, "ABC123-42")
        XCTAssertNil(duplicateSample)
        XCTAssertEqual(manager.state.sensorSerial, "ABC123")
        XCTAssertEqual(manager.state.lastReadingDate, date)
        XCTAssertEqual(manager.state.latestSampleNumber, 42)
        XCTAssertEqual(manager.glucoseDisplay as? MicroTechGlucoseReading, reading)
    }

    func testAcceptRejectsOlderSampleNumberForSameSensorSerial() {
        let manager = MicroTechCGMManager()
        let firstReading = makeReading(
            sampleNumber: 42,
            glucoseMgdl: 123,
            receivedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let latestReading = makeReading(
            sampleNumber: 43,
            glucoseMgdl: 124,
            receivedAt: Date(timeIntervalSince1970: 1_700_000_300)
        )
        let oldReading = makeReading(
            sampleNumber: 42,
            glucoseMgdl: 122,
            receivedAt: Date(timeIntervalSince1970: 1_700_000_600)
        )

        XCTAssertEqual(manager.accept(firstReading)?.syncIdentifier, "ABC123-42")
        XCTAssertEqual(manager.accept(latestReading)?.syncIdentifier, "ABC123-43")
        XCTAssertNil(manager.accept(oldReading))
        XCTAssertEqual(manager.state.latestSampleNumber, 43)
        XCTAssertEqual(manager.state.latestReading, latestReading)
        XCTAssertEqual(manager.glucoseDisplay as? MicroTechGlucoseReading, latestReading)
    }

    func testAcceptAllowsSampleNumberRolloverForSameSensorSerial() {
        let manager = MicroTechCGMManager()
        let lastBeforeRollover = makeReading(
            sampleNumber: 65535,
            glucoseMgdl: 123,
            receivedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let firstAfterRollover = makeReading(
            sampleNumber: 1,
            glucoseMgdl: 124,
            receivedAt: Date(timeIntervalSince1970: 1_700_000_120)
        )

        XCTAssertEqual(manager.accept(lastBeforeRollover)?.syncIdentifier, "ABC123-65535")
        XCTAssertEqual(manager.accept(firstAfterRollover)?.syncIdentifier, "ABC123-1")
        XCTAssertEqual(manager.state.latestSampleNumber, 1)
        XCTAssertEqual(manager.state.latestReading, firstAfterRollover)
    }

    func testAcceptAllowsSampleZeroAfterRolloverForSameSensorSerial() {
        let manager = MicroTechCGMManager()
        let lastBeforeRollover = makeReading(
            sampleNumber: 65535,
            glucoseMgdl: 123,
            receivedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let zeroAfterRollover = makeReading(
            sampleNumber: 0,
            glucoseMgdl: 124,
            receivedAt: Date(timeIntervalSince1970: 1_700_000_060)
        )

        XCTAssertEqual(manager.accept(lastBeforeRollover)?.syncIdentifier, "ABC123-65535")
        XCTAssertEqual(manager.accept(zeroAfterRollover)?.syncIdentifier, "ABC123-0")
        XCTAssertEqual(manager.state.latestSampleNumber, 0)
        XCTAssertEqual(manager.state.latestReading, zeroAfterRollover)
    }

    func testAcceptRejectsInvalidTherapyReadings() {
        let manager = MicroTechCGMManager()
        let date = Date(timeIntervalSince1970: 1_700_000_000)

        XCTAssertNil(manager.accept(makeReading(sampleNumber: 42, glucoseMgdl: 123, receivedAt: date, quality: 1)))
        XCTAssertNil(manager.accept(makeReading(sampleNumber: 43, glucoseMgdl: 39, receivedAt: date)))
        XCTAssertNil(manager.accept(makeReading(sampleNumber: 44, glucoseMgdl: 401, receivedAt: date)))
        XCTAssertNil(manager.state.latestReading)
        XCTAssertNil(manager.state.latestSampleNumber)
    }

    func testUploadReadingsSetterUpdatesStateAndRemoteSyncPreference() {
        let manager = MicroTechCGMManager()

        manager.uploadReadings = true

        XCTAssertTrue(manager.state.uploadReadings)
        XCTAssertTrue(manager.shouldSyncToRemoteService)

        manager.uploadReadings = false

        XCTAssertFalse(manager.state.uploadReadings)
        XCTAssertFalse(manager.shouldSyncToRemoteService)
    }

    func testStatusHighlightOnlyShowsSignalLossForExpiredReading() {
        XCTAssertNil(MicroTechCGMManager().cgmStatusHighlight)

        var state = MicroTechCGMManagerState()
        state.sensorSerial = "ABC123"
        XCTAssertNil(MicroTechCGMManager(state: state).cgmStatusHighlight)

        state.lastReadingDate = Date().addingTimeInterval(-14 * 60)
        XCTAssertNil(MicroTechCGMManager(state: state).cgmStatusHighlight)

        state.lastReadingDate = Date().addingTimeInterval(-16 * 60)
        let highlight = MicroTechCGMManager(state: state).cgmStatusHighlight as? MicroTechDeviceStatusHighlight
        XCTAssertEqual(highlight?.localizedMessage, "Signal\nLoss")
        XCTAssertEqual(highlight?.imageName, "exclamationmark.circle.fill")
        XCTAssertEqual(highlight?.state, .warning)
    }

    func testScanForSensorWithoutConfiguredSensorStartsNearbyBluetoothScan() {
        let bluetoothManager = FakeMicroTechBluetoothManager()
        let manager = MicroTechCGMManager(
            state: MicroTechCGMManagerState(),
            bluetoothManagerFactory: { bluetoothManager }
        )

        XCTAssertTrue(manager.scanForSensor())

        XCTAssertEqual(bluetoothManager.scanRemoteIdentifiers, [nil])
        XCTAssertTrue(manager.isScanning)
    }

    func testBluetoothScanLogsAreForwardedToDeviceLog() {
        let bluetoothManager = FakeMicroTechBluetoothManager()
        let manager = MicroTechCGMManager(
            state: MicroTechCGMManagerState(),
            bluetoothManagerFactory: { bluetoothManager }
        )
        let delegate = TestCGMManagerDelegate(expectedReadingResultCount: 0)
        let logQueue = DispatchQueue(label: "MicroTechCGMManagerTests.bluetoothLogs")
        manager.delegateQueue = logQueue
        manager.cgmManagerDelegate = delegate

        XCTAssertTrue(manager.scanForSensor())
        bluetoothManager.logHandler?("didDiscover peripheral TEST, advertisedName Optional(\"LinX-NEARBY123\")", .connection)
        bluetoothManager.logHandler?("peripheral configure failed TEST, name LinX-NEARBY123, error timeout", .error)
        logQueue.sync {}

        XCTAssertTrue(delegate.loggedEvents.contains { event in
            event.type == .connection && event.message.contains("didDiscover peripheral TEST")
        })
        XCTAssertTrue(delegate.loggedEvents.contains { event in
            event.type == .error && event.message.contains("peripheral configure failed TEST")
        })
    }

    func testDiagnosticErrorFieldsIncludeDomainCodeAndDescription() {
        let error = NSError(
            domain: "MicroTechCGMTests",
            code: 42,
            userInfo: [NSLocalizedDescriptionKey: "diagnostic failure"]
        )

        XCTAssertEqual(
            MicroTechDiagnosticLog.errorFields(error),
            "errorDomain=MicroTechCGMTests errorCode=42 errorDescription=diagnostic failure"
        )
        XCTAssertEqual(
            MicroTechDiagnosticLog.errorFields(nil),
            "errorDomain=nil errorCode=nil errorDescription=nil"
        )
    }

    func testScanLifecycleLogsStartedFoundAcceptedRejectedStoppedAndTimeout() {
        let identifier = UUID(uuidString: "00000000-0000-0000-0000-000000000123")!

        XCTAssertEqual(
            MicroTechBluetoothManager.scanStartedLogMessage(requestedIdentifier: identifier),
            "stage=scan event=started requestedIdentifier=\(identifier)"
        )
        XCTAssertEqual(
            MicroTechBluetoothManager.scanFoundLogMessage(
                identifier: identifier,
                name: nil,
                advertisement: "localName=LinX-ABC123",
                rssi: -55
            ),
            "stage=scan event=found identifier=\(identifier) name=nil advertisement=localName=LinX-ABC123 rssi=-55"
        )
        XCTAssertEqual(
            MicroTechBluetoothManager.scanDecisionLogMessage(
                accepted: true,
                identifier: identifier,
                reason: "requestedIdentifier"
            ),
            "stage=scan event=accepted identifier=\(identifier) reason=requestedIdentifier"
        )
        XCTAssertEqual(
            MicroTechBluetoothManager.scanDecisionLogMessage(
                accepted: false,
                identifier: identifier,
                reason: "delegateRejected"
            ),
            "stage=scan event=rejected identifier=\(identifier) reason=delegateRejected"
        )
        XCTAssertEqual(
            MicroTechBluetoothManager.scanStoppedLogMessage(reason: "timeout"),
            "stage=scan event=stopped reason=timeout"
        )
        XCTAssertEqual(
            MicroTechBluetoothManager.scanTimeoutLogMessage(requestedIdentifier: identifier),
            "stage=scan event=timeout requestedIdentifier=\(identifier)"
        )
        XCTAssertEqual(
            MicroTechBluetoothManager.scanStartedLogMessage(requestedIdentifier: nil),
            "stage=scan event=started requestedIdentifier=nil"
        )
        XCTAssertEqual(
            MicroTechBluetoothManager.broadcastScanStartedLogMessage(requestedIdentifier: identifier),
            "stage=broadcast event=started requestedIdentifier=\(identifier)"
        )
        XCTAssertEqual(
            MicroTechBluetoothManager.broadcastFoundLogMessage(
                identifier: identifier,
                name: nil,
                advertisement: "localName=AiDEX X-ABC123",
                rssi: -61
            ),
            "stage=broadcast event=found identifier=\(identifier) name=nil advertisement=localName=AiDEX X-ABC123 rssi=-61"
        )
        XCTAssertEqual(
            MicroTechBluetoothManager.broadcastScanStoppedLogMessage(reason: "timeout"),
            "stage=broadcast event=stopped reason=timeout"
        )
        XCTAssertEqual(
            MicroTechBluetoothManager.broadcastScanTimeoutLogMessage(requestedIdentifier: identifier),
            "stage=broadcast event=timeout requestedIdentifier=\(identifier)"
        )
    }

    func testAdvertisementDescriptionRecursivelySerializesAllValuesInStableOrder() {
        let advertisementData: [String: Any] = [
            "nested": [
                "z": [NSNumber(value: 7), "LinX", Data([0xDE, 0xAD])],
                "a": CBUUID(string: "1808"),
            ],
            CBAdvertisementDataServiceDataKey: [
                CBUUID(string: "FFF0"): Data([0x10, 0x20, 0x00, 0xFE]),
            ],
            CBAdvertisementDataManufacturerDataKey: Data([0x01, 0xAB, 0x00, 0xFF]),
        ]

        XCTAssertEqual(
            MicroTechBluetoothManager.advertisementDescription(advertisementData),
            "kCBAdvDataManufacturerData=Data(length=4,hex=01AB00FF),kCBAdvDataServiceData={FFF0=Data(length=4,hex=102000FE)},nested={a=1808,z=[7,LinX,Data(length=2,hex=DEAD)]}"
        )
    }

    func testDiscoveryLogsUseOnlyBroadcastStageInBroadcastMode() {
        let identifier = UUID(uuidString: "00000000-0000-0000-0000-000000000123")!

        let directLogs = MicroTechBluetoothManager.discoveryLogMessages(
            connectionMode: .direct,
            identifier: identifier,
            name: "AiDEX X-ABC123",
            advertisement: "payload=Data(length=3,hex=590102)",
            rssi: -61
        )
        XCTAssertTrue(directLogs.contains { $0.contains("stage=scan event=found") })
        XCTAssertFalse(directLogs.contains { $0.contains("stage=broadcast event=found") })

        let broadcastLogs = MicroTechBluetoothManager.discoveryLogMessages(
            connectionMode: .broadcast,
            identifier: identifier,
            name: "AiDEX X-ABC123",
            advertisement: "payload=Data(length=3,hex=590102)",
            rssi: -61
        )
        XCTAssertTrue(broadcastLogs.contains { $0.contains("stage=broadcast event=found") })
        XCTAssertFalse(broadcastLogs.contains { $0.contains("stage=scan event=found") })
    }

    func testBroadcastFilteredScanFallsBackToUnfilteredScan() {
        let identifier = UUID(uuidString: "00000000-0000-0000-0000-000000000123")!

        XCTAssertEqual(
            MicroTechBluetoothManager.broadcastScanServiceFilter(phase: .filtered)?.map(\.uuidString),
            [MicroTechAidexProfile.serviceUUID.uuidString]
        )
        XCTAssertNil(MicroTechBluetoothManager.broadcastScanServiceFilter(phase: .unfiltered))
        XCTAssertEqual(
            MicroTechBluetoothManager.broadcastScanStartedLogMessage(requestedIdentifier: identifier, phase: .unfiltered),
            "stage=broadcast event=started phase=unfiltered requestedIdentifier=\(identifier) services=nil"
        )
        XCTAssertEqual(
            MicroTechBluetoothManager.broadcastScanFallbackLogMessage(requestedIdentifier: identifier),
            "stage=broadcast event=fallback reason=filteredTimeout requestedIdentifier=\(identifier) nextServices=nil"
        )
    }

    func testBroadcastPostFilterOnlyForwardsMicroTechManufacturerData() {
        XCTAssertTrue(MicroTechBluetoothManager.isMicroTechBroadcastAdvertisement([
            CBAdvertisementDataManufacturerDataKey: Data([0x59, 0x00, 0x42, 0x54]),
        ]))
        XCTAssertFalse(MicroTechBluetoothManager.isMicroTechBroadcastAdvertisement([
            CBAdvertisementDataManufacturerDataKey: Data([0xAA, 0x55]),
        ]))
        XCTAssertFalse(MicroTechBluetoothManager.isMicroTechBroadcastAdvertisement([:]))
    }

    func testConnectionLifecycleLogsAttemptedSucceededFailedTimeoutAndDisconnected() {
        let identifier = UUID(uuidString: "00000000-0000-0000-0000-000000000123")!
        let error = NSError(
            domain: "CoreBluetooth",
            code: 7,
            userInfo: [NSLocalizedDescriptionKey: "connection lost"]
        )

        XCTAssertEqual(
            MicroTechBluetoothManager.connectionLogMessage(event: "attempted", identifier: identifier),
            "stage=connect event=attempted identifier=\(identifier)"
        )
        XCTAssertEqual(
            MicroTechBluetoothManager.connectionLogMessage(event: "succeeded", identifier: identifier),
            "stage=connect event=succeeded identifier=\(identifier)"
        )
        XCTAssertEqual(
            MicroTechBluetoothManager.connectionLogMessage(event: "failed", identifier: identifier, error: error),
            "stage=connect event=failed identifier=\(identifier) errorDomain=CoreBluetooth errorCode=7 errorDescription=connection lost"
        )
        XCTAssertEqual(
            MicroTechBluetoothManager.connectionLogMessage(event: "timeout", identifier: identifier),
            "stage=connect event=timeout identifier=\(identifier)"
        )
        XCTAssertEqual(
            MicroTechBluetoothManager.connectionLogMessage(event: "disconnected", identifier: identifier),
            "stage=connect event=disconnected identifier=\(identifier)"
        )
    }

    func testExpectedCancellationDisconnectCallbackLogsNormalDisconnectedWithoutMissingManager() {
        let identifier = UUID(uuidString: "00000000-0000-0000-0000-000000000123")!
        let state = MicroTechDisconnectCallbackState()
        var entries: [(message: String, type: MicroTechBluetoothLogType)] = []

        state.expectCancellation(identifier: identifier)
        let result = state.handleConnectionEnd(
            callback: "didDisconnectPeripheral",
            identifier: identifier,
            error: nil,
            managerPresent: false,
            log: { entries.append(($0, $1)) }
        )

        XCTAssertEqual(result, .expectedCancellation)
        XCTAssertEqual(entries.map(\.message), [
            "stage=connect event=disconnected identifier=\(identifier)",
        ])
        guard let type = entries.first?.type else {
            return XCTFail("Expected disconnected log entry")
        }
        guard case .connection = type else {
            return XCTFail("Expected normal connection log type")
        }
    }

    func testExpectedCancellationFailToConnectUsesSameNormalEndPathAndConsumesMarker() {
        let identifier = UUID(uuidString: "00000000-0000-0000-0000-000000000123")!
        let state = MicroTechDisconnectCallbackState()
        var entries: [(message: String, type: MicroTechBluetoothLogType)] = []
        let error = NSError(
            domain: "CoreBluetooth",
            code: 7,
            userInfo: [NSLocalizedDescriptionKey: "cancelled during connect"]
        )

        state.expectCancellation(identifier: identifier)
        let expectedResult = state.handleConnectionEnd(
            callback: "didFailToConnect",
            identifier: identifier,
            error: error,
            managerPresent: true,
            log: { entries.append(($0, $1)) }
        )
        let consumedResult = state.handleConnectionEnd(
            callback: "didFailToConnect",
            identifier: identifier,
            error: nil,
            managerPresent: false,
            log: { entries.append(($0, $1)) }
        )

        XCTAssertEqual(expectedResult, .expectedCancellation)
        XCTAssertEqual(consumedResult, .missingPeripheralManager)
        XCTAssertEqual(
            entries.first?.message,
            "stage=connect event=disconnected identifier=\(identifier) errorDomain=CoreBluetooth errorCode=7 errorDescription=cancelled during connect"
        )
        XCTAssertEqual(entries.first?.type, .connection)
        XCTAssertFalse(entries.contains { $0.message.contains("event=failed") })
        XCTAssertEqual(
            entries.last?.message,
            "stage=callback event=ignored callback=didFailToConnect identifier=\(identifier) reason=missingPeripheralManager"
        )
    }

    func testRestoredPeripheralLogsRestorationSourceAndIdentifier() {
        let identifier = UUID(uuidString: "00000000-0000-0000-0000-000000000123")!

        XCTAssertEqual(
            MicroTechBluetoothManager.restoredPeripheralLogMessage(
                identifier: identifier,
                source: .coreBluetoothRestore
            ),
            "stage=restore event=restored identifier=\(identifier) source=CoreBluetoothRestore"
        )
        XCTAssertEqual(
            MicroTechBluetoothManager.restoredPeripheralLogMessage(
                identifier: identifier,
                source: .retrievePeripherals
            ),
            "stage=restore event=restored identifier=\(identifier) source=retrievePeripherals"
        )
    }

    func testBluetoothStateLossLogsOldAndNewStateAndStoppedOperation() {
        XCTAssertEqual(
            MicroTechBluetoothManager.bluetoothStateChangedLogMessage(
                oldState: .poweredOn,
                newState: .poweredOff,
                stoppedOperation: "scan"
            ),
            "stage=bluetooth event=state_changed oldState=poweredOn newState=poweredOff stoppedOperation=scan"
        )
        XCTAssertEqual(
            MicroTechBluetoothManager.bluetoothStateChangedLogMessage(
                oldState: nil,
                newState: .poweredOn,
                stoppedOperation: nil
            ),
            "stage=bluetooth event=state_changed oldState=nil newState=poweredOn stoppedOperation=nil"
        )
    }

    func testMissingPeripheralManagerCallbackIncludesIdentifierAndCallback() {
        let identifier = UUID(uuidString: "00000000-0000-0000-0000-000000000123")!

        XCTAssertEqual(
            MicroTechBluetoothManager.missingPeripheralManagerLogMessage(
                callback: "didConnect",
                identifier: identifier
            ),
            "stage=callback event=ignored callback=didConnect identifier=\(identifier) reason=missingPeripheralManager"
        )
        XCTAssertEqual(
            MicroTechBluetoothManager.missingPeripheralManagerLogMessage(
                callback: "didFailToConnect",
                identifier: identifier
            ),
            "stage=callback event=ignored callback=didFailToConnect identifier=\(identifier) reason=missingPeripheralManager"
        )
    }

    func testBluetoothSendAndReceiveTypesMapToDeviceLogTypes() {
        let bluetoothManager = FakeMicroTechBluetoothManager()
        let manager = MicroTechCGMManager(
            state: MicroTechCGMManagerState(),
            bluetoothManagerFactory: { bluetoothManager }
        )
        let delegate = TestCGMManagerDelegate(expectedReadingResultCount: 0)
        let logQueue = DispatchQueue(label: "MicroTechCGMManagerTests.bluetoothDataLogs")
        manager.delegateQueue = logQueue
        manager.cgmManagerDelegate = delegate

        XCTAssertTrue(manager.scanForSensor())
        bluetoothManager.logHandler?("send payload", .send)
        bluetoothManager.logHandler?("receive payload", .receive)
        logQueue.sync {}

        XCTAssertTrue(delegate.loggedEvents.contains { $0.type == .send && $0.message == "send payload" })
        XCTAssertTrue(delegate.loggedEvents.contains { $0.type == .receive && $0.message == "receive payload" })
    }

    func testDiscoverServicesErrorLogsFailedWithNSErrorFields() {
        assertGattErrorLog(
            callback: .discoverServices,
            service: MicroTechAidexProfile.serviceUUID,
            characteristic: nil,
            operation: "discoverServices"
        )
    }

    func testDiscoverCharacteristicsErrorLogsFailedWithNSErrorFields() {
        assertGattErrorLog(
            callback: .discoverCharacteristics,
            service: MicroTechAidexProfile.serviceUUID,
            characteristic: nil,
            operation: "discoverCharacteristics"
        )
    }

    func testNotificationStateErrorLogsFailedWithNSErrorFields() {
        assertGattErrorLog(
            callback: .notificationState,
            service: nil,
            characteristic: MicroTechAidexProfile.f002UUID,
            operation: "notificationState"
        )
    }

    func testReadCallbackErrorLogsFailedWithNSErrorFields() {
        assertGattErrorLog(
            callback: .read,
            service: nil,
            characteristic: MicroTechAidexProfile.f002UUID,
            operation: "read"
        )
    }

    func testReadCallbackWithoutValueLogsFailedReasonMissingValue() throws {
        let identifier = UUID(uuidString: "00000000-0000-0000-0000-000000000123")!
        let state = MicroTechGattOperationState()
        var entries: [MicroTechGattLogEntry] = []
        XCTAssertNoThrow(try state.begin(.read(MicroTechAidexProfile.f002UUID)))

        state.handleValueCallback(
            identifier: identifier,
            characteristic: MicroTechAidexProfile.f002UUID,
            error: nil,
            value: nil,
            log: { entries.append(contentsOf: $0.entries) }
        )

        XCTAssertEqual(try state.wait(timeout: 0.01), .completed)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.type, .error)
        XCTAssertEqual(
            entries.first?.message,
            "stage=gatt operation=read event=failed identifier=\(identifier) service=nil characteristic=\(MicroTechAidexProfile.f002UUID.uuidString) reason=missingValue"
        )
    }

    func testNotificationCallbackErrorLogsFailedWithNSErrorFields() {
        assertGattErrorLog(
            callback: .notificationValue,
            service: nil,
            characteristic: MicroTechAidexProfile.f003UUID,
            operation: "notificationValue"
        )
    }

    func testNotificationValueLogsAttemptedBeforeCallbacks() throws {
        let identifier = UUID(uuidString: "00000000-0000-0000-0000-000000000123")!
        let state = MicroTechGattOperationState()
        var entries: [MicroTechGattLogEntry] = []
        XCTAssertNoThrow(try state.begin(.notification(MicroTechAidexProfile.f003UUID)))

        state.handleOperationCallback(
            callback: .notificationState,
            identifier: identifier,
            service: nil,
            characteristic: MicroTechAidexProfile.f003UUID,
            error: nil,
            log: { entries.append(contentsOf: $0.entries) }
        )

        XCTAssertEqual(try state.wait(timeout: 0.01), .completed)
        XCTAssertEqual(
            entries.last?.message,
            "stage=gatt operation=notificationValue event=attempted identifier=\(identifier) service=nil characteristic=\(MicroTechAidexProfile.f003UUID.uuidString)"
        )
    }

    func testNotificationCallbackWithoutValueLogsFailedReasonMissingValue() {
        let identifier = UUID(uuidString: "00000000-0000-0000-0000-000000000123")!
        let state = MicroTechGattOperationState()
        var entries: [MicroTechGattLogEntry] = []

        state.handleValueCallback(
            identifier: identifier,
            characteristic: MicroTechAidexProfile.f003UUID,
            error: nil,
            value: nil,
            log: { entries.append(contentsOf: $0.entries) }
        )

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.type, .error)
        XCTAssertEqual(
            entries.first?.message,
            "stage=gatt operation=notificationValue event=failed identifier=\(identifier) service=nil characteristic=\(MicroTechAidexProfile.f003UUID.uuidString) reason=missingValue"
        )
    }

    func testNotificationCallbackLogsSucceededAndFullPayload() {
        let identifier = UUID(uuidString: "00000000-0000-0000-0000-000000000123")!
        let payload = Data(0...63)
        let state = MicroTechGattOperationState()
        var entries: [MicroTechGattLogEntry] = []

        state.handleValueCallback(
            identifier: identifier,
            characteristic: MicroTechAidexProfile.f003UUID,
            error: nil,
            value: payload,
            log: { entries.append(contentsOf: $0.entries) }
        )

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.type, .receive)
        XCTAssertTrue(entries.first?.message.contains("valueLength=64") == true)
        XCTAssertTrue(entries.first?.message.contains("valueHex=\(payload.microTechHexadecimalString)") == true)
        XCTAssertTrue(entries.first?.message.hasSuffix("3C3D3E3F") == true)
        XCTAssertFalse(entries.first?.message.contains("rawPrefix") == true)
        XCTAssertFalse(entries.first?.message.contains("prefix") == true)
        XCTAssertFalse(entries.first?.message.contains("...") == true)
    }

    func testWriteCallbackErrorLogsFailedWithNSErrorFields() {
        assertGattErrorLog(
            callback: .write,
            service: nil,
            characteristic: MicroTechAidexProfile.f001UUID,
            operation: "write"
        )
    }

    func testGattOperationTimeoutLogsPendingOperationAndTarget() {
        let identifier = UUID(uuidString: "00000000-0000-0000-0000-000000000123")!

        XCTAssertEqual(
            MicroTechPeripheralManager.gattTimeoutLogMessage(
                identifier: identifier,
                operation: .discoverCharacteristics(MicroTechAidexProfile.serviceUUID)
            ),
            "stage=gatt event=timeout identifier=\(identifier) pendingOperation=discoverCharacteristics service=\(MicroTechAidexProfile.serviceUUID.uuidString) characteristic=nil"
        )
        XCTAssertEqual(
            MicroTechPeripheralManager.gattTimeoutLogMessage(
                identifier: identifier,
                operation: .write(MicroTechAidexProfile.f001UUID)
            ),
            "stage=gatt event=timeout identifier=\(identifier) pendingOperation=write service=nil characteristic=\(MicroTechAidexProfile.f001UUID.uuidString)"
        )
    }

    func testWriteTimeoutInvalidatesSessionRejectsRetryAndIgnoresOldCallback() throws {
        let identifier = UUID(uuidString: "00000000-0000-0000-0000-000000000123")!
        let state = MicroTechGattOperationState()
        var timeoutCount = 0
        var entries: [MicroTechGattLogEntry] = []
        try state.begin(.write(MicroTechAidexProfile.f001UUID))

        XCTAssertEqual(
            try state.wait(timeout: 0.001, onTimeout: {
                if state.requestDisconnect() {
                    timeoutCount += 1
                }
            }),
            .timedOut
        )
        XCTAssertEqual(timeoutCount, 1)
        XCTAssertFalse(state.requestDisconnect())
        for operation in [
            MicroTechGattOperation.notification(MicroTechAidexProfile.f003UUID),
            .read(MicroTechAidexProfile.f002UUID),
            .write(MicroTechAidexProfile.f001UUID),
        ] {
            XCTAssertThrowsError(try state.begin(operation)) { error in
                XCTAssertEqual(error as? MicroTechPeripheralManagerError, .notConnected)
            }
        }
        XCTAssertThrowsError(try state.validateImmediateCommand()) { error in
            XCTAssertEqual(error as? MicroTechPeripheralManagerError, .notConnected)
        }

        state.handleOperationCallback(
            callback: .write,
            identifier: identifier,
            service: nil,
            characteristic: MicroTechAidexProfile.f001UUID,
            error: nil,
            log: { entries.append(contentsOf: $0.entries) }
        )

        XCTAssertEqual(entries.filter { $0.message.contains("event=ignored") }.count, 1)
        XCTAssertTrue(entries[0].message.contains("reason=sessionInvalidated"))
        XCTAssertFalse(entries[0].message.contains("event=succeeded"))
    }

    func testReadTimeoutInvalidatesSessionRejectsRetryAndIgnoresOldCallback() throws {
        let identifier = UUID(uuidString: "00000000-0000-0000-0000-000000000123")!
        let state = MicroTechGattOperationState()
        var entries: [MicroTechGattLogEntry] = []
        try state.begin(.read(MicroTechAidexProfile.f002UUID))

        XCTAssertEqual(try state.wait(timeout: 0.001), .timedOut)
        XCTAssertThrowsError(try state.begin(.read(MicroTechAidexProfile.f002UUID))) { error in
            XCTAssertEqual(error as? MicroTechPeripheralManagerError, .notConnected)
        }

        let value = state.handleValueCallback(
            identifier: identifier,
            characteristic: MicroTechAidexProfile.f002UUID,
            error: nil,
            value: Data([0x01, 0x02]),
            log: { entries.append(contentsOf: $0.entries) }
        )

        XCTAssertNil(value)
        XCTAssertEqual(entries.filter { $0.message.contains("event=ignored") }.count, 1)
        XCTAssertTrue(entries[0].message.contains("reason=sessionInvalidated"))
        XCTAssertFalse(entries[0].message.contains("event=succeeded"))
    }

    func testDisconnectCompletesPendingReadWithNotConnectedWithoutTimeout() throws {
        try assertDisconnectCompletesPendingOperation(.read(MicroTechAidexProfile.f002UUID))
    }

    func testDisconnectCompletesPendingWriteWithNotConnectedWithoutTimeout() throws {
        try assertDisconnectCompletesPendingOperation(.write(MicroTechAidexProfile.f001UUID))
    }

    func testSynchronousWriteRejectionLogsFailedWithFullPayloadAndNoAttempt() {
        let identifier = UUID(uuidString: "00000000-0000-0000-0000-000000000123")!
        let payload = Data(0...63)
        let state = MicroTechGattOperationState()
        state.invalidateSession()
        var entries: [MicroTechGattLogEntry] = []

        do {
            try state.begin(.write(MicroTechAidexProfile.f001UUID))
            XCTFail("Expected invalidated session to reject write")
        } catch {
            entries.append(MicroTechPeripheralManager.writeSynchronousFailureLogEntry(
                identifier: identifier,
                characteristic: MicroTechAidexProfile.f001UUID,
                value: payload,
                writeType: .withResponse,
                error: error
            ))
        }

        assertSynchronousWriteFailure(entries, payload: payload, expectedError: .notConnected)
    }

    func testPendingOperationWriteRejectionLogsFailedWithoutFalseAttempt() throws {
        let identifier = UUID(uuidString: "00000000-0000-0000-0000-000000000123")!
        let payload = Data(0...63)
        let state = MicroTechGattOperationState()
        var entries: [MicroTechGattLogEntry] = []
        try state.begin(.read(MicroTechAidexProfile.f002UUID))

        do {
            try state.begin(.write(MicroTechAidexProfile.f001UUID))
            XCTFail("Expected pending operation to reject write")
        } catch {
            entries.append(MicroTechPeripheralManager.writeSynchronousFailureLogEntry(
                identifier: identifier,
                characteristic: MicroTechAidexProfile.f001UUID,
                value: payload,
                writeType: .withResponse,
                error: error
            ))
        }

        assertSynchronousWriteFailure(entries, payload: payload, expectedError: .invalidCommand)
    }

    func testWriteWithResponseLogsAttemptSucceededAndFullPayload() throws {
        let identifier = UUID(uuidString: "00000000-0000-0000-0000-000000000123")!
        let payload = Data(0...63)
        let expectedHex = payload.microTechHexadecimalString
        let attempted = MicroTechPeripheralManager.writeAttemptLogEntry(
            identifier: identifier,
            characteristic: MicroTechAidexProfile.f001UUID,
            value: payload,
            writeType: .withResponse
        )
        let state = MicroTechGattOperationState()
        var succeeded: [MicroTechGattLogEntry] = []
        XCTAssertNoThrow(try state.begin(.write(MicroTechAidexProfile.f001UUID)))
        state.handleOperationCallback(
            callback: .write,
            identifier: identifier,
            service: nil,
            characteristic: MicroTechAidexProfile.f001UUID,
            error: nil,
            log: { succeeded.append(contentsOf: $0.entries) }
        )

        XCTAssertEqual(try state.wait(timeout: 0.01), .completed)
        XCTAssertEqual(attempted.type, .send)
        XCTAssertTrue(attempted.message.contains("event=attempted"))
        XCTAssertTrue(attempted.message.contains("writeType=withResponse"))
        XCTAssertTrue(attempted.message.contains("payloadLength=64"))
        XCTAssertTrue(attempted.message.contains("payloadHex=\(expectedHex)"))
        XCTAssertTrue(attempted.message.hasSuffix("3C3D3E3F"))
        XCTAssertFalse(attempted.message.contains("rawPrefix"))
        XCTAssertFalse(attempted.message.contains("prefix"))
        XCTAssertFalse(attempted.message.contains("..."))
        XCTAssertEqual(succeeded.count, 1)
        XCTAssertEqual(succeeded.first?.type, .send)
        XCTAssertTrue(succeeded.first?.message.contains("event=succeeded") == true)
    }

    func testWriteWithoutResponseLogsAttemptAndSubmittedWithoutSuccess() {
        let identifier = UUID(uuidString: "00000000-0000-0000-0000-000000000123")!
        let payload = Data(0...63)
        let entries = MicroTechPeripheralManager.writeWithoutResponseLogEntries(
            identifier: identifier,
            characteristic: MicroTechAidexProfile.f001UUID,
            value: payload
        )

        XCTAssertEqual(entries.map(\.type), [.send, .send])
        XCTAssertEqual(entries.filter { $0.message.contains("event=attempted") }.count, 1)
        XCTAssertEqual(entries.filter { $0.message.contains("event=submitted") }.count, 1)
        XCTAssertTrue(entries.last?.message.contains("noCallback=true") == true)
        XCTAssertFalse(entries.contains { $0.message.contains("event=succeeded") })
        XCTAssertTrue(entries.first?.message.contains("payloadLength=64") == true)
        XCTAssertTrue(entries.first?.message.hasSuffix("3C3D3E3F") == true)
        XCTAssertFalse(entries.first?.message.contains("rawPrefix") == true)
        XCTAssertFalse(entries.first?.message.contains("prefix") == true)
        XCTAssertFalse(entries.first?.message.contains("...") == true)
    }

    func testMatchingWriteCallbackLogsSucceededAndCompletesPendingWrite() throws {
        let identifier = UUID(uuidString: "00000000-0000-0000-0000-000000000123")!
        let state = MicroTechGattOperationState()
        var entries: [MicroTechGattLogEntry] = []
        try state.begin(.write(MicroTechAidexProfile.f001UUID))

        state.handleOperationCallback(
            callback: .write,
            identifier: identifier,
            service: nil,
            characteristic: MicroTechAidexProfile.f001UUID,
            error: nil,
            log: { entries.append(contentsOf: $0.entries) }
        )

        XCTAssertEqual(try state.wait(timeout: 0.01), .completed)
        XCTAssertEqual(entries.filter { $0.message.contains("event=succeeded") }.count, 1)
        XCTAssertFalse(entries.contains { $0.message.contains("event=ignored") })
    }

    func testLateWriteCallbackLogsIgnoredWithoutSuccess() {
        let identifier = UUID(uuidString: "00000000-0000-0000-0000-000000000123")!
        let state = MicroTechGattOperationState()
        var entries: [MicroTechGattLogEntry] = []

        state.handleOperationCallback(
            callback: .write,
            identifier: identifier,
            service: nil,
            characteristic: MicroTechAidexProfile.f001UUID,
            error: nil,
            log: { entries.append(contentsOf: $0.entries) }
        )

        XCTAssertEqual(entries.count, 1)
        XCTAssertTrue(entries[0].message.contains("event=ignored"))
        XCTAssertTrue(entries[0].message.contains("reason=missingPendingOperation"))
        XCTAssertTrue(entries[0].message.contains("pendingOperation=nil"))
        XCTAssertFalse(entries[0].message.contains("event=succeeded"))
    }

    func testFailedPendingWriteIgnoresMatchingLateCallbackAndPreservesFailure() throws {
        let identifier = UUID(uuidString: "00000000-0000-0000-0000-000000000123")!
        let state = MicroTechGattOperationState()
        var entries: [MicroTechGattLogEntry] = []
        try state.begin(.write(MicroTechAidexProfile.f001UUID))
        state.failPending(MicroTechPeripheralManagerError.notConnected)

        state.handleOperationCallback(
            callback: .write,
            identifier: identifier,
            service: nil,
            characteristic: MicroTechAidexProfile.f001UUID,
            error: nil,
            log: { entries.append(contentsOf: $0.entries) }
        )

        XCTAssertFalse(entries.contains { $0.message.contains("event=succeeded") })
        XCTAssertEqual(entries.filter { $0.message.contains("event=ignored") }.count, 1)
        XCTAssertTrue(entries[0].message.contains("reason=operationAlreadyCompleted"))
        XCTAssertThrowsError(try state.wait(timeout: 0.01)) { error in
            XCTAssertEqual(error as? MicroTechPeripheralManagerError, .notConnected)
        }
    }

    func testFailedPendingReadIgnoresMatchingLateCallbackAndPreservesFailure() throws {
        let identifier = UUID(uuidString: "00000000-0000-0000-0000-000000000123")!
        let state = MicroTechGattOperationState()
        var entries: [MicroTechGattLogEntry] = []
        try state.begin(.read(MicroTechAidexProfile.f002UUID))
        state.failPending(MicroTechPeripheralManagerError.notConnected)

        let value = state.handleValueCallback(
            identifier: identifier,
            characteristic: MicroTechAidexProfile.f002UUID,
            error: nil,
            value: Data(0...63),
            log: { entries.append(contentsOf: $0.entries) }
        )

        XCTAssertNil(value)
        XCTAssertFalse(entries.contains { $0.message.contains("event=succeeded") })
        XCTAssertEqual(entries.filter { $0.message.contains("event=ignored") }.count, 1)
        XCTAssertTrue(entries[0].message.contains("reason=operationAlreadyCompleted"))
        XCTAssertThrowsError(try state.wait(timeout: 0.01)) { error in
            XCTAssertEqual(error as? MicroTechPeripheralManagerError, .notConnected)
        }
    }

    func testMismatchedWriteCallbackLogsIgnoredWithoutCompletingPendingRead() throws {
        let identifier = UUID(uuidString: "00000000-0000-0000-0000-000000000123")!
        let state = MicroTechGattOperationState()
        var entries: [MicroTechGattLogEntry] = []
        try state.begin(.read(MicroTechAidexProfile.f002UUID))

        state.handleOperationCallback(
            callback: .write,
            identifier: identifier,
            service: nil,
            characteristic: MicroTechAidexProfile.f001UUID,
            error: nil,
            log: { entries.append(contentsOf: $0.entries) }
        )

        XCTAssertEqual(entries.count, 1)
        XCTAssertTrue(entries[0].message.contains("event=ignored"))
        XCTAssertTrue(entries[0].message.contains("reason=pendingOperationMismatch"))
        XCTAssertTrue(entries[0].message.contains("pendingOperation=read"))
        XCTAssertFalse(entries[0].message.contains("event=succeeded"))
        XCTAssertEqual(try state.wait(timeout: 0.001), .timedOut)
    }

    func testWithoutResponseWriteCallbackCannotLogSucceeded() {
        let identifier = UUID(uuidString: "00000000-0000-0000-0000-000000000123")!
        let state = MicroTechGattOperationState()
        var entries = MicroTechPeripheralManager.writeWithoutResponseLogEntries(
            identifier: identifier,
            characteristic: MicroTechAidexProfile.f001UUID,
            value: Data(0...63)
        )

        state.handleOperationCallback(
            callback: .write,
            identifier: identifier,
            service: nil,
            characteristic: MicroTechAidexProfile.f001UUID,
            error: nil,
            log: { entries.append(contentsOf: $0.entries) }
        )

        XCTAssertFalse(entries.contains { $0.message.contains("event=succeeded") })
        XCTAssertTrue(entries.last?.message.contains("event=ignored") == true)
        XCTAssertTrue(entries.last?.message.contains("reason=missingPendingOperation") == true)
    }

    func testNotificationStateProducesOneBatchWithAttemptBeforeAnyValueResult() throws {
        let identifier = UUID(uuidString: "00000000-0000-0000-0000-000000000123")!
        let state = MicroTechGattOperationState()
        var batches: [MicroTechGattLogBatch] = []
        try state.begin(.notification(MicroTechAidexProfile.f003UUID))

        state.handleOperationCallback(
            callback: .notificationState,
            identifier: identifier,
            service: nil,
            characteristic: MicroTechAidexProfile.f003UUID,
            error: nil,
            log: { batches.append($0) }
        )

        XCTAssertEqual(try state.wait(timeout: 0.05), .completed)
        XCTAssertEqual(batches.count, 1)
        XCTAssertEqual(batches[0].entries.count, 2)
        XCTAssertTrue(batches[0].entries[0].message.contains("operation=notificationState event=succeeded"))
        XCTAssertTrue(batches[0].entries[1].message.contains("operation=notificationValue event=attempted"))
    }

    func testBlockedLogHandlerDoesNotDisableOperationDeadline() throws {
        let identifier = UUID(uuidString: "00000000-0000-0000-0000-000000000123")!
        let state = MicroTechGattOperationState()
        let logQueue = MicroTechGattLogQueue(label: "MicroTechCGMManagerTests.blockedDeadlineLog")
        let handlerStarted = DispatchSemaphore(value: 0)
        let releaseHandler = DispatchSemaphore(value: 0)
        let waitStarted = DispatchSemaphore(value: 0)
        let waitCompleted = expectation(description: "read wait reached its deadline")
        let result = ThreadSafeWaitOutcome()
        let events = ThreadSafeMessages()
        try state.begin(.read(MicroTechAidexProfile.f002UUID))

        logQueue.handler = { message, _ in
            events.append(message)
            if message.contains("event=attempted") {
                handlerStarted.signal()
                releaseHandler.wait()
            }
        }
        logQueue.submit(MicroTechPeripheralManager.gattAttemptLogEntry(
            identifier: identifier,
            operation: .read(MicroTechAidexProfile.f002UUID)
        ))
        XCTAssertEqual(handlerStarted.wait(timeout: .now() + 1), .success)

        DispatchQueue.global().async {
            waitStarted.signal()
            result.capture {
                try state.wait(
                    timeout: 0.05,
                    onTimeout: {
                        logQueue.submit(MicroTechGattLogEntry(
                            message: MicroTechPeripheralManager.gattTimeoutLogMessage(
                                identifier: identifier,
                                operation: .read(MicroTechAidexProfile.f002UUID)
                            ),
                            type: .error
                        ))
                    }
                )
            }
            waitCompleted.fulfill()
        }

        XCTAssertEqual(waitStarted.wait(timeout: .now() + 1), .success)
        wait(for: [waitCompleted], timeout: 1)
        XCTAssertEqual(result.waitResult, .timedOut)
        releaseHandler.signal()
        logQueue.flush()
        let values = events.values
        let attemptedIndex = values.firstIndex { $0.contains("operation=read event=attempted") }
        let timeoutIndex = values.firstIndex { $0.contains("event=timeout") }
        XCTAssertNotNil(attemptedIndex)
        XCTAssertNotNil(timeoutIndex)
        XCTAssertLessThan(attemptedIndex!, timeoutIndex!)
    }

    func testSerialLogQueueDoesNotLetSlowHandlerBlockReadCompletion() throws {
        let identifier = UUID(uuidString: "00000000-0000-0000-0000-000000000123")!
        let state = MicroTechGattOperationState()
        let logQueue = MicroTechGattLogQueue(
            label: "MicroTechCGMManagerTests.slowGattLogHandler"
        )
        let events = ThreadSafeMessages()
        let handlerStarted = DispatchSemaphore(value: 0)
        let releaseHandler = DispatchSemaphore(value: 0)
        logQueue.handler = { message, _ in
            events.append(message)
            if message.contains("event=attempted") {
                handlerStarted.signal()
                releaseHandler.wait()
            }
        }
        try state.begin(.read(MicroTechAidexProfile.f002UUID))
        logQueue.submit(MicroTechPeripheralManager.gattAttemptLogEntry(
            identifier: identifier,
            operation: .read(MicroTechAidexProfile.f002UUID)
        ))
        XCTAssertEqual(handlerStarted.wait(timeout: .now() + 1), .success)

        state.handleValueCallback(
            identifier: identifier,
            characteristic: MicroTechAidexProfile.f002UUID,
            error: nil,
            value: Data([0x01, 0x02]),
            log: logQueue.submit
        )

        XCTAssertEqual(try state.wait(timeout: 0.05), .completed)
        releaseHandler.signal()
        logQueue.flush()
        let values = events.values
        let attemptedIndex = try XCTUnwrap(values.firstIndex { $0.contains("operation=read event=attempted") })
        let resultIndex = try XCTUnwrap(values.firstIndex { $0.contains("operation=read event=succeeded") })
        XCTAssertLessThan(attemptedIndex, resultIndex)
    }

    func testLogQueueReplaysBoundedPreHandlerEntriesInOrder() {
        let logQueue = MicroTechGattLogQueue(
            label: "MicroTechCGMManagerTests.preHandlerReplay",
            preHandlerBufferCapacity: 3
        )
        let events = ThreadSafeMessages()

        for index in 0..<5 {
            logQueue.submit(MicroTechGattLogEntry(message: "message-\(index)", type: .connection))
        }
        logQueue.flush()
        logQueue.handler = { message, _ in
            events.append(message)
        }
        logQueue.flush()

        XCTAssertEqual(events.values, ["message-2", "message-3", "message-4"])
    }

    func testCompletedOrderedStreamsAreRemovedWithoutBreakingOutOfOrderDelivery() {
        let logQueue = MicroTechGattLogQueue(
            label: "MicroTechCGMManagerTests.completedOrderedStreams"
        )
        let events = ThreadSafeMessages()
        logQueue.handler = { message, _ in
            events.append(message)
        }

        for index in 0..<100 {
            let streamIdentifier = UUID()
            logQueue.submit(MicroTechGattLogBatch(
                streamIdentifier: streamIdentifier,
                sequence: 1,
                entries: [MicroTechGattLogEntry(message: "\(index)-1", type: .connection)],
                completesStream: true
            ))
            logQueue.submit(MicroTechGattLogBatch(
                streamIdentifier: streamIdentifier,
                sequence: 0,
                entries: [MicroTechGattLogEntry(message: "\(index)-0", type: .connection)]
            ))
        }
        logQueue.flush()

        XCTAssertEqual(logQueue.orderedStreamCount, 0)
        XCTAssertEqual(events.values.count, 200)
        for index in 0..<100 {
            XCTAssertEqual(
                Array(events.values[(index * 2)..<(index * 2 + 2)]),
                ["\(index)-0", "\(index)-1"]
            )
        }
    }

    func testReadWaiterReturnsOnlyAfterBatchSubmitReturns() throws {
        try assertWaiterReturnsOnlyAfterBatchSubmit(.read(MicroTechAidexProfile.f002UUID))
    }

    func testWriteWaiterReturnsOnlyAfterBatchSubmitReturns() throws {
        try assertWaiterReturnsOnlyAfterBatchSubmit(.write(MicroTechAidexProfile.f001UUID))
    }

    private func assertWaiterReturnsOnlyAfterBatchSubmit(
        _ operation: MicroTechGattOperation,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let identifier = UUID(uuidString: "00000000-0000-0000-0000-000000000123")!
        let state = MicroTechGattOperationState()
        let waitStarted = DispatchSemaphore(value: 0)
        let waiterReturned = DispatchSemaphore(value: 0)
        let submitEntered = DispatchSemaphore(value: 0)
        let releaseSubmit = DispatchSemaphore(value: 0)
        let callbackFinished = expectation(description: "read callback finished")
        let outcome = ThreadSafeWaitOutcome()
        try state.begin(operation)

        DispatchQueue.global().async {
            waitStarted.signal()
            outcome.capture {
                try state.wait(timeout: 1)
            }
            waiterReturned.signal()
        }
        XCTAssertEqual(waitStarted.wait(timeout: .now() + 1), .success, file: file, line: line)

        DispatchQueue.global().async {
            let submit: (MicroTechGattLogBatch) -> Void = { _ in
                submitEntered.signal()
                releaseSubmit.wait()
            }
            switch operation {
            case .read(let characteristic):
                state.handleValueCallback(
                    identifier: identifier,
                    characteristic: characteristic,
                    error: nil,
                    value: Data([0x01, 0x02]),
                    log: submit
                )
            case .write(let characteristic):
                state.handleOperationCallback(
                    callback: .write,
                    identifier: identifier,
                    service: nil,
                    characteristic: characteristic,
                    error: nil,
                    log: submit
                )
            case .discoverServices, .discoverCharacteristics, .notification:
                XCTFail("Unsupported operation", file: file, line: line)
            }
            callbackFinished.fulfill()
        }

        XCTAssertEqual(submitEntered.wait(timeout: .now() + 1), .success, file: file, line: line)
        XCTAssertEqual(waiterReturned.wait(timeout: .now() + 0.05), .timedOut, file: file, line: line)
        releaseSubmit.signal()
        wait(for: [callbackFinished], timeout: 1)
        XCTAssertEqual(waiterReturned.wait(timeout: .now() + 1), .success, file: file, line: line)
        XCTAssertEqual(outcome.waitResult, .completed, file: file, line: line)
    }

    func testConcurrentNotificationCallbacksLogAttemptBeforeValueResult() throws {
        let identifier = UUID(uuidString: "00000000-0000-0000-0000-000000000123")!
        let state = MicroTechGattOperationState()
        let logQueue = MicroTechGattLogQueue(
            label: "MicroTechCGMManagerTests.concurrentNotificationLogs"
        )
        let events = ThreadSafeMessages()
        let firstLogStarted = DispatchSemaphore(value: 0)
        let releaseFirstLog = DispatchSemaphore(value: 0)
        let notificationStateFinished = expectation(description: "notification state callback finished")
        let notificationValueFinished = expectation(description: "notification value callback finished")
        try state.begin(.notification(MicroTechAidexProfile.f003UUID))

        logQueue.handler = { message, _ in
            events.append(message)
            if message.contains("operation=notificationState") {
                firstLogStarted.signal()
                releaseFirstLog.wait()
            }
        }
        DispatchQueue.global().async {
            state.handleOperationCallback(
                callback: .notificationState,
                identifier: identifier,
                service: nil,
                characteristic: MicroTechAidexProfile.f003UUID,
                error: nil,
                log: logQueue.submit
            )
            notificationStateFinished.fulfill()
        }
        XCTAssertEqual(firstLogStarted.wait(timeout: .now() + 1), .success)

        DispatchQueue.global().async {
            state.handleValueCallback(
                identifier: identifier,
                characteristic: MicroTechAidexProfile.f003UUID,
                error: nil,
                value: Data([0x01, 0x02]),
                log: logQueue.submit
            )
            notificationValueFinished.fulfill()
        }
        wait(for: [notificationStateFinished, notificationValueFinished], timeout: 1)
        releaseFirstLog.signal()
        logQueue.flush()

        let values = events.values
        let attemptedIndex = values.firstIndex { $0.contains("operation=notificationValue event=attempted") }
        let resultIndex = values.firstIndex { $0.contains("operation=notificationValue event=succeeded") }
        XCTAssertNotNil(attemptedIndex)
        XCTAssertNotNil(resultIndex)
        XCTAssertLessThan(attemptedIndex!, resultIndex!)
    }

    func testGattLogBatchSubmissionAllowsHandlerToReenterOperationState() throws {
        let identifier = UUID(uuidString: "00000000-0000-0000-0000-000000000123")!
        let state = MicroTechGattOperationState()
        let logQueue = MicroTechGattLogQueue(label: "MicroTechCGMManagerTests.reentrantGattLog")
        let reentered = expectation(description: "handler reentered state")
        try state.begin(.notification(MicroTechAidexProfile.f003UUID))

        logQueue.handler = { message, _ in
            guard message.contains("operation=notificationState") else {
                return
            }
            _ = state.handleValueCallback(
                identifier: identifier,
                characteristic: MicroTechAidexProfile.f003UUID,
                error: nil,
                value: Data([0x01]),
                log: logQueue.submit
            )
            _ = logQueue.handler
            logQueue.handler = nil
            reentered.fulfill()
        }
        state.handleOperationCallback(
            callback: .notificationState,
            identifier: identifier,
            service: nil,
            characteristic: MicroTechAidexProfile.f003UUID,
            error: nil,
            log: logQueue.submit
        )

        wait(for: [reentered], timeout: 1)
        logQueue.flush()
    }

    func testSetupInstallsOnboardingLogHandlerBeforeScanning() {
        let bluetoothManager = FakeMicroTechBluetoothManager()
        bluetoothManager.scanLog = ("stage=scan event=started", .connection)
        let manager = MicroTechCGMManager(
            state: MicroTechCGMManagerState(),
            bluetoothManagerFactory: { bluetoothManager }
        )
        let coordinator = MicroTechUICoordinator(
            colorPalette: EnvironmentValues().colorPalette,
            displayGlucosePreference: DisplayGlucosePreference(displayGlucoseUnit: Self.mgdlUnit),
            allowDebugFeatures: false,
            makeCGMManager: { manager }
        )
        var receivedMessages: [String] = []
        coordinator.onboardingDeviceLogHandler = { _, _, _, message in
            receivedMessages.append(message)
        }

        coordinator.completeSetup()

        XCTAssertEqual(receivedMessages.filter { $0 == "stage=scan event=started" }, ["stage=scan event=started"])
    }

    func testSetupViewContinueActionDoesNotExposeConnectionMode() {
        var didContinue = false
        let view = MicroTechSetupView(
            didContinue: { didContinue = true },
            didCancel: nil
        )

        view.didContinue?()

        XCTAssertTrue(didContinue)
    }

    func testSetupCoordinatorExposesParameterlessDirectAction() {
        var state = MicroTechCGMManagerState()
        state.connectionMode = .broadcast
        let bluetoothManager = FakeMicroTechBluetoothManager()
        let manager = MicroTechCGMManager(
            state: state,
            bluetoothManagerFactory: { bluetoothManager }
        )
        let coordinator = MicroTechUICoordinator(
            colorPalette: EnvironmentValues().colorPalette,
            displayGlucosePreference: DisplayGlucosePreference(displayGlucoseUnit: Self.mgdlUnit),
            allowDebugFeatures: false,
            makeCGMManager: { manager }
        )
        let completeSetup: () -> Void = coordinator.completeSetup

        completeSetup()

        XCTAssertEqual(manager.state.connectionMode, .direct)
        XCTAssertEqual(bluetoothManager.scanRemoteIdentifiers, [nil])
    }

    func testBluetoothLogHandlerInstallationAndBufferedCallbackDoNotWaitForManagerStateLock() {
        let bluetoothManager = ReentrantLogHandlerMicroTechBluetoothManager()
        let manager = MicroTechCGMManager(
            state: MicroTechCGMManagerState(),
            bluetoothManagerFactory: { bluetoothManager }
        )
        let completed = expectation(description: "log handler installed without manager state lock")
        bluetoothManager.onSetLogHandler = { handler in
            _ = manager.state
            handler?("stage=bluetooth event=state state=poweredOn", .connection)
            _ = manager.state
        }
        manager.onboardingDeviceLogHandler = { _, _, _ in
            _ = manager.state
        }

        DispatchQueue.global().async {
            _ = manager.scanForSensor()
            completed.fulfill()
        }

        wait(for: [completed], timeout: 1)
    }

    func testConfigureCacheAndMissingAttributeLogsUseStableStageEvents() {
        let identifier = UUID(uuidString: "00000000-0000-0000-0000-000000000123")!
        let services = [
            MicroTechAidexProfile.serviceUUID,
            CBUUID(string: "180F"),
        ]
        let characteristics = [
            MicroTechAidexProfile.f003UUID,
            MicroTechAidexProfile.f001UUID,
            MicroTechAidexProfile.f002UUID,
        ]

        XCTAssertEqual(
            MicroTechPeripheralManager.discoveryCacheHitLogEntry(
                identifier: identifier,
                operation: .discoverServices(MicroTechAidexProfile.serviceUUID),
                discoveredUUIDs: services
            ).message,
            "stage=gatt operation=discoverServices event=cacheHit identifier=\(identifier) service=\(MicroTechAidexProfile.serviceUUID.uuidString) characteristic=nil discoveredServices=[\(MicroTechAidexProfile.serviceUUID.uuidString),180F]"
        )
        XCTAssertEqual(
            MicroTechPeripheralManager.discoveryCacheHitLogEntry(
                identifier: identifier,
                operation: .discoverCharacteristics(MicroTechAidexProfile.serviceUUID),
                discoveredUUIDs: characteristics
            ).message,
            "stage=gatt operation=discoverCharacteristics event=cacheHit identifier=\(identifier) service=\(MicroTechAidexProfile.serviceUUID.uuidString) characteristic=nil discoveredCharacteristics=[\(MicroTechAidexProfile.f001UUID.uuidString),\(MicroTechAidexProfile.f002UUID.uuidString),\(MicroTechAidexProfile.f003UUID.uuidString)]"
        )
        XCTAssertEqual(
            MicroTechPeripheralManager.configureMissingAttributeLogEntry(
                identifier: identifier,
                service: MicroTechAidexProfile.serviceUUID,
                characteristic: nil,
                discoveredUUIDs: []
            ).message,
            "stage=gatt operation=configure event=failed identifier=\(identifier) service=\(MicroTechAidexProfile.serviceUUID.uuidString) characteristic=nil reason=missingService discoveredServices=[]"
        )
        XCTAssertEqual(
            MicroTechPeripheralManager.configureMissingAttributeLogEntry(
                identifier: identifier,
                service: MicroTechAidexProfile.serviceUUID,
                characteristic: MicroTechAidexProfile.f002UUID,
                discoveredUUIDs: [MicroTechAidexProfile.f001UUID, MicroTechAidexProfile.f003UUID]
            ).message,
            "stage=gatt operation=configure event=failed identifier=\(identifier) service=\(MicroTechAidexProfile.serviceUUID.uuidString) characteristic=\(MicroTechAidexProfile.f002UUID.uuidString) reason=missingCharacteristic discoveredCharacteristics=[\(MicroTechAidexProfile.f001UUID.uuidString),\(MicroTechAidexProfile.f003UUID.uuidString)]"
        )
    }

    func testDiscoverSuccessAndSynchronousFailuresIncludeActualContext() {
        let identifier = UUID(uuidString: "00000000-0000-0000-0000-000000000123")!
        let services = [CBUUID(string: "180F"), MicroTechAidexProfile.serviceUUID]
        let characteristics = [MicroTechAidexProfile.f003UUID, MicroTechAidexProfile.f001UUID]

        XCTAssertEqual(
            MicroTechPeripheralManager.callbackLogEntries(
                callback: .discoverServices,
                identifier: identifier,
                service: MicroTechAidexProfile.serviceUUID,
                characteristic: nil,
                error: nil,
                value: nil,
                discoveredServiceUUIDs: services
            ).first?.message,
            "stage=gatt operation=discoverServices event=succeeded identifier=\(identifier) service=\(MicroTechAidexProfile.serviceUUID.uuidString) characteristic=nil discoveredServices=[\(MicroTechAidexProfile.serviceUUID.uuidString),180F]"
        )
        XCTAssertEqual(
            MicroTechPeripheralManager.callbackLogEntries(
                callback: .discoverCharacteristics,
                identifier: identifier,
                service: MicroTechAidexProfile.serviceUUID,
                characteristic: nil,
                error: nil,
                value: nil,
                discoveredCharacteristicUUIDs: characteristics
            ).first?.message,
            "stage=gatt operation=discoverCharacteristics event=succeeded identifier=\(identifier) service=\(MicroTechAidexProfile.serviceUUID.uuidString) characteristic=nil discoveredCharacteristics=[\(MicroTechAidexProfile.f001UUID.uuidString),\(MicroTechAidexProfile.f003UUID.uuidString)]"
        )

        let subscribeError = MicroTechPeripheralManagerError.unknownCharacteristic(MicroTechAidexProfile.f003UUID)
        XCTAssertEqual(
            MicroTechPeripheralManager.synchronousFailureLogEntry(
                identifier: identifier,
                operation: .notification(MicroTechAidexProfile.f003UUID),
                error: subscribeError
            ).message,
            "stage=gatt operation=notificationState event=failed identifier=\(identifier) service=nil characteristic=\(MicroTechAidexProfile.f003UUID.uuidString) reason=synchronousFailure \(MicroTechDiagnosticLog.errorFields(subscribeError))"
        )
        let readError = MicroTechPeripheralManagerError.notConnected
        XCTAssertEqual(
            MicroTechPeripheralManager.synchronousFailureLogEntry(
                identifier: identifier,
                operation: .read(MicroTechAidexProfile.f002UUID),
                error: readError
            ).message,
            "stage=gatt operation=read event=failed identifier=\(identifier) service=nil characteristic=\(MicroTechAidexProfile.f002UUID.uuidString) reason=synchronousFailure \(MicroTechDiagnosticLog.errorFields(readError))"
        )
    }

    func testOnboardingLogHandlerReceivesScanFailureBeforeManagerCreation() {
        var state = MicroTechCGMManagerState()
        state.sensorSerial = "TEST-LINX-SERIAL-0001"
        let bluetoothManager = FakeMicroTechBluetoothManager()
        bluetoothManager.scanLog = ("stage=scan event=failed reason=timeout", .error)
        let manager = MicroTechCGMManager(
            state: state,
            bluetoothManagerFactory: { bluetoothManager }
        )
        let onboardingDelegate = TestCGMOnboardingDelegate(expectedCreateCount: 0, expectedOnboardCount: 0)
        let coordinator = MicroTechUICoordinator(
            colorPalette: EnvironmentValues().colorPalette,
            displayGlucosePreference: DisplayGlucosePreference(displayGlucoseUnit: Self.mgdlUnit),
            allowDebugFeatures: false,
            makeCGMManager: { manager }
        )
        var receivedEvents: [(managerIdentifier: String, deviceIdentifier: String?, type: DeviceLogEntryType, message: String)] = []
        coordinator.cgmManagerOnboardingDelegate = onboardingDelegate
        coordinator.onboardingDeviceLogHandler = { managerIdentifier, deviceIdentifier, type, message in
            receivedEvents.append((managerIdentifier, deviceIdentifier, type, message))
        }

        coordinator.completeSetup()

        XCTAssertEqual(receivedEvents.filter { $0.message == "stage=scan event=failed reason=timeout" }.count, 1)
        let event = receivedEvents.first { $0.message == "stage=scan event=failed reason=timeout" }
        XCTAssertEqual(event?.managerIdentifier, MicroTechCGMManager.pluginIdentifier)
        XCTAssertEqual(event?.deviceIdentifier, "TEST-LINX-SERIAL-0001")
        XCTAssertEqual(event?.type, .error)
        XCTAssertTrue(onboardingDelegate.createdManagers.isEmpty)
        XCTAssertTrue(onboardingDelegate.onboardedManagers.isEmpty)
    }

    func testFormalDelegateSuppressesOnboardingHandlerToAvoidDuplicateLogs() {
        let bluetoothManager = FakeMicroTechBluetoothManager()
        let manager = MicroTechCGMManager(
            state: MicroTechCGMManagerState(),
            bluetoothManagerFactory: { bluetoothManager }
        )
        let delegate = TestCGMManagerDelegate(expectedReadingResultCount: 0)
        let delegateQueue = DispatchQueue(label: "MicroTechCGMManagerTests.formalDelegateLogs")
        var onboardingMessages: [String] = []
        manager.onboardingDeviceLogHandler = { _, _, message in
            onboardingMessages.append(message)
        }

        XCTAssertTrue(manager.scanForSensor())
        bluetoothManager.logHandler?("onboarding-only", .error)
        manager.delegateQueue = delegateQueue
        manager.cgmManagerDelegate = delegate
        bluetoothManager.logHandler?("formal-only", .error)
        delegateQueue.sync {}

        XCTAssertEqual(onboardingMessages.filter { $0 == "onboarding-only" }, ["onboarding-only"])
        XCTAssertFalse(onboardingMessages.contains("formal-only"))
        XCTAssertEqual(delegate.loggedEvents.filter { $0.message == "formal-only" }.count, 1)
        XCTAssertFalse(delegate.loggedEvents.contains { $0.message == "onboarding-only" })
    }

    func testConcurrentFormalDelegateTransitionLogsEveryMessageExactlyOnce() {
        let bluetoothManager = FakeMicroTechBluetoothManager()
        let manager = MicroTechCGMManager(
            state: MicroTechCGMManagerState(),
            bluetoothManagerFactory: { bluetoothManager }
        )
        let delegate = TestCGMManagerDelegate(expectedReadingResultCount: 0)
        let delegateQueue = DispatchQueue(label: "MicroTechCGMManagerTests.concurrentFormalDelegateLogs")
        let onboardingMessages = ThreadSafeMessages()
        manager.onboardingDeviceLogHandler = { _, _, message in
            onboardingMessages.append(message)
        }
        XCTAssertTrue(manager.scanForSensor())

        let messageCount = 500
        let start = DispatchSemaphore(value: 0)
        let group = DispatchGroup()
        let producerQueue = DispatchQueue(label: "MicroTechCGMManagerTests.concurrentLogProducer", attributes: .concurrent)
        for index in 0..<messageCount {
            group.enter()
            producerQueue.async {
                start.wait()
                bluetoothManager.logHandler?("message-\(index)", .error)
                group.leave()
            }
        }
        group.enter()
        producerQueue.async {
            start.wait()
            manager.delegateQueue = delegateQueue
            manager.cgmManagerDelegate = delegate
            group.leave()
        }

        for _ in 0...messageCount {
            start.signal()
        }
        XCTAssertEqual(group.wait(timeout: .now() + 5), .success)
        delegateQueue.sync {}

        let allMessages = onboardingMessages.values + delegate.loggedEvents.map(\.message)
        for index in 0..<messageCount {
            XCTAssertEqual(allMessages.filter { $0 == "message-\(index)" }.count, 1, "message-\(index)")
        }
    }

    func testFailedSetupDoesNotCreateOrOnboardManager() {
        let bluetoothManager = FakeMicroTechBluetoothManager()
        let manager = MicroTechCGMManager(
            state: MicroTechCGMManagerState(),
            bluetoothManagerFactory: { bluetoothManager }
        )
        manager.delete {}
        let onboardingDelegate = TestCGMOnboardingDelegate(expectedCreateCount: 0, expectedOnboardCount: 0)
        let coordinator = MicroTechUICoordinator(
            colorPalette: EnvironmentValues().colorPalette,
            displayGlucosePreference: DisplayGlucosePreference(displayGlucoseUnit: Self.mgdlUnit),
            allowDebugFeatures: false,
            makeCGMManager: { manager }
        )
        coordinator.cgmManagerOnboardingDelegate = onboardingDelegate

        coordinator.completeSetup()

        XCTAssertTrue(bluetoothManager.scanRemoteIdentifiers.isEmpty)
        XCTAssertTrue(onboardingDelegate.createdManagers.isEmpty)
        XCTAssertTrue(onboardingDelegate.onboardedManagers.isEmpty)
    }

    func testNearbyScanConnectsDiscoveredLinxAndSavesSensor() throws {
        let bluetoothManager = FakeMicroTechBluetoothManager()
        let manager = MicroTechCGMManager(
            state: MicroTechCGMManagerState(),
            bluetoothManagerFactory: { bluetoothManager }
        )
        let remoteIdentifier = UUID(uuidString: "00000000-0000-0000-0000-000000000321")!
        let material = MicroTechAidexKeyMaterial.derive(serial: "NEARBY123")
        let peripheralSession = FakeMicroTechPeripheralSession(
            deviceIdentifier: remoteIdentifier,
            deviceName: "LinX-NEARBY123",
            f002Challenge: try encryptedChallenge(for: material),
            failurePoint: .read,
            subscriptionFailures: [MicroTechAidexProfile.f001UUID]
        )

        XCTAssertTrue(manager.scanForSensor())
        manager.connectDiscoveredSensor(peripheralSession: peripheralSession)

        XCTAssertEqual(manager.state.remoteIdentifier, remoteIdentifier)
        XCTAssertEqual(manager.state.deviceName, "LinX-NEARBY123")
        XCTAssertEqual(manager.state.sensorSerial, "NEARBY123")
        XCTAssertFalse(manager.cgmManagerStatus.hasValidSensorSession)
        XCTAssertTrue((bluetoothManager.delegate as AnyObject?) is MicroTechSensor)
    }

    func testNearbyScanConnectsDiscoveredAidexAndSavesSensor() throws {
        let bluetoothManager = FakeMicroTechBluetoothManager()
        let manager = MicroTechCGMManager(
            state: MicroTechCGMManagerState(),
            bluetoothManagerFactory: { bluetoothManager }
        )
        let remoteIdentifier = UUID(uuidString: "00000000-0000-0000-0000-000000000654")!
        let material = MicroTechAidexKeyMaterial.derive(serial: "AIDEX123")
        let peripheralSession = FakeMicroTechPeripheralSession(
            deviceIdentifier: remoteIdentifier,
            deviceName: "AiDEX-AIDEX123",
            f002Challenge: try encryptedChallenge(for: material),
            failurePoint: .read,
            subscriptionFailures: [MicroTechAidexProfile.f001UUID]
        )

        XCTAssertTrue(manager.scanForSensor())
        manager.connectDiscoveredSensor(peripheralSession: peripheralSession)

        XCTAssertEqual(manager.state.remoteIdentifier, remoteIdentifier)
        XCTAssertEqual(manager.state.deviceName, "AiDEX-AIDEX123")
        XCTAssertEqual(manager.state.sensorSerial, "AIDEX123")
        XCTAssertFalse(manager.cgmManagerStatus.hasValidSensorSession)
        XCTAssertTrue((bluetoothManager.delegate as AnyObject?) is MicroTechSensor)
    }

    func testConfigureSensorFromDeviceNameSavesSerialAndStartsScan() {
        let bluetoothManager = FakeMicroTechBluetoothManager()
        let manager = MicroTechCGMManager(
            state: MicroTechCGMManagerState(),
            bluetoothManagerFactory: { bluetoothManager }
        )

        XCTAssertTrue(manager.configureSensor(deviceNameOrSerial: "AiDEX-222227HAUZ"))
        XCTAssertEqual(manager.state.deviceName, "AiDEX-222227HAUZ")
        XCTAssertEqual(manager.state.sensorSerial, "222227HAUZ")

        XCTAssertTrue(manager.scanForSensor())
        XCTAssertEqual(bluetoothManager.scanRemoteIdentifiers, [nil])
    }

    func testConfigureSensorRejectsEmptyInput() {
        let manager = MicroTechCGMManager()

        XCTAssertFalse(manager.configureSensor(deviceNameOrSerial: "   "))
        XCTAssertNil(manager.state.deviceName)
        XCTAssertNil(manager.state.sensorSerial)
    }

    func testScanForSensorStartsBluetoothScanForSavedSensor() {
        let remoteIdentifier = UUID(uuidString: "00000000-0000-0000-0000-000000000123")!
        var state = MicroTechCGMManagerState()
        state.remoteIdentifier = remoteIdentifier
        state.deviceName = "LinX-ABC123"
        state.sensorSerial = "ABC123"
        let bluetoothManager = FakeMicroTechBluetoothManager()
        let manager = MicroTechCGMManager(
            state: state,
            bluetoothManagerFactory: { bluetoothManager }
        )

        XCTAssertTrue(manager.scanForSensor())

        XCTAssertEqual(bluetoothManager.scanRemoteIdentifiers, [remoteIdentifier])
        XCTAssertTrue(manager.isScanning)
    }

    func testRepeatedScanAndFetchKeepActiveSensorAcceptingReadings() {
        let remoteIdentifier = UUID(uuidString: "00000000-0000-0000-0000-000000000123")!
        var state = MicroTechCGMManagerState()
        state.remoteIdentifier = remoteIdentifier
        state.deviceName = "LinX-ABC123"
        state.sensorSerial = "ABC123"
        let bluetoothManager = FakeMicroTechBluetoothManager()
        let manager = MicroTechCGMManager(
            state: state,
            bluetoothManagerFactory: { bluetoothManager }
        )
        let delegate = TestCGMManagerDelegate(expectedReadingResultCount: 1)
        manager.delegateQueue = .main
        manager.cgmManagerDelegate = delegate

        XCTAssertTrue(manager.scanForSensor())
        guard let firstSensor = bluetoothManager.delegate as? MicroTechSensor else {
            return XCTFail("Expected scan to install a MicroTechSensor delegate")
        }

        XCTAssertTrue(manager.scanForSensor())
        manager.fetchNewDataIfNeeded { result in
            if case .noData = result {
                return
            }
            XCTFail("Expected fetch to report no data")
        }

        XCTAssertTrue((bluetoothManager.delegate as AnyObject?) === firstSensor)
        manager.microTechSensorDidConnect(firstSensor, session: makeSession())
        manager.microTechSensor(
            firstSensor,
            didRead: makeReading(
                sampleNumber: 42,
                glucoseMgdl: 123,
                receivedAt: Date(timeIntervalSince1970: 1_700_000_000)
            )
        )

        wait(for: [delegate.readingResultsExpectation], timeout: 1)
        XCTAssertEqual(delegate.newDataSampleSyncIdentifiers, ["ABC123-42"])
        XCTAssertEqual(manager.state.latestSampleNumber, 42)
    }

    func testActiveSensorDisconnectRestartsScanForSavedPeripheral() {
        let remoteIdentifier = UUID(uuidString: "00000000-0000-0000-0000-000000000123")!
        var state = MicroTechCGMManagerState()
        state.remoteIdentifier = remoteIdentifier
        state.deviceName = "LinX-ABC123"
        state.sensorSerial = "ABC123"
        let bluetoothManager = FakeMicroTechBluetoothManager()
        var retryBlocks: [() -> Void] = []
        let manager = MicroTechCGMManager(
            state: state,
            bluetoothManagerFactory: { bluetoothManager },
            bluetoothRetryScheduler: { retryBlocks.append($0) }
        )

        XCTAssertTrue(manager.scanForSensor())
        guard let sensor = bluetoothManager.delegate as? MicroTechSensor else {
            return XCTFail("Expected scan to install a MicroTechSensor delegate")
        }
        manager.microTechSensorDidConnect(sensor, session: makeSession(remoteIdentifier: remoteIdentifier))
        bluetoothManager.isScanning = false
        bluetoothManager.isConnected = false

        manager.microTechSensorDidDisconnect(sensor)

        XCTAssertEqual(bluetoothManager.scanRemoteIdentifiers, [remoteIdentifier])
        XCTAssertEqual(retryBlocks.count, 1)
        guard retryBlocks.count == 1 else {
            return
        }

        retryBlocks[0]()

        XCTAssertEqual(bluetoothManager.scanRemoteIdentifiers, [remoteIdentifier, remoteIdentifier])
        XCTAssertTrue(bluetoothManager.isScanning)
    }

    func testFetchDisconnectsStaleConnectedSensorSoBluetoothCanReconnect() {
        let remoteIdentifier = UUID(uuidString: "00000000-0000-0000-0000-000000000123")!
        var state = MicroTechCGMManagerState()
        state.remoteIdentifier = remoteIdentifier
        state.deviceName = "LinX-ABC123"
        state.sensorSerial = "ABC123"
        state.lastReadingDate = Date(timeIntervalSinceNow: -16 * 60)
        let bluetoothManager = FakeMicroTechBluetoothManager()
        bluetoothManager.isConnected = true
        let manager = MicroTechCGMManager(
            state: state,
            bluetoothManagerFactory: { bluetoothManager }
        )
        let fetchCompleted = expectation(description: "fetch completed")

        XCTAssertTrue(manager.scanForSensor())
        manager.fetchNewDataIfNeeded { result in
            if case .noData = result {
                fetchCompleted.fulfill()
            } else {
                XCTFail("Expected stale reconnect fetch to report no data")
            }
        }

        wait(for: [fetchCompleted], timeout: 1)
        XCTAssertEqual(bluetoothManager.disconnectCallCount, 1)
        XCTAssertEqual(bluetoothManager.scanRemoteIdentifiers, [remoteIdentifier])
    }

    func testFetchDisconnectsConnectedSensorWhenNoReadingArrivesAfterConnectTimeout() {
        let remoteIdentifier = UUID(uuidString: "00000000-0000-0000-0000-000000000123")!
        var now = Date(timeIntervalSince1970: 1_700_000_000)
        var state = MicroTechCGMManagerState()
        state.remoteIdentifier = remoteIdentifier
        state.deviceName = "LinX-ABC123"
        state.sensorSerial = "ABC123"
        let bluetoothManager = FakeMicroTechBluetoothManager()
        let manager = MicroTechCGMManager(
            state: state,
            bluetoothManagerFactory: { bluetoothManager },
            dateProvider: { now }
        )
        let fetchCompleted = expectation(description: "fetch completed")

        XCTAssertTrue(manager.scanForSensor())
        guard let sensor = bluetoothManager.delegate as? MicroTechSensor else {
            return XCTFail("Expected scan to install a MicroTechSensor delegate")
        }
        manager.microTechSensorDidConnect(sensor, session: makeSession(remoteIdentifier: remoteIdentifier))
        bluetoothManager.isConnected = true
        now = now.addingTimeInterval(16 * 60)

        manager.fetchNewDataIfNeeded { result in
            if case .noData = result {
                fetchCompleted.fulfill()
            } else {
                XCTFail("Expected no-reading reconnect fetch to report no data")
            }
        }

        wait(for: [fetchCompleted], timeout: 1)
        XCTAssertEqual(bluetoothManager.disconnectCallCount, 1)
        XCTAssertEqual(bluetoothManager.scanRemoteIdentifiers, [remoteIdentifier, remoteIdentifier])
    }

    func testConnectedSensorWatchdogReconnectsWithoutFetchWhenNoReadingArrives() throws {
        let remoteIdentifier = UUID(uuidString: "00000000-0000-0000-0000-000000000123")!
        var now = Date(timeIntervalSince1970: 1_700_000_000)
        var scheduledWatchdogs: [(TimeInterval, () -> Void)] = []
        var state = MicroTechCGMManagerState()
        state.remoteIdentifier = remoteIdentifier
        state.deviceName = "LinX-ABC123"
        state.sensorSerial = "ABC123"
        let bluetoothManager = FakeMicroTechBluetoothManager()
        let manager = MicroTechCGMManager(
            state: state,
            bluetoothManagerFactory: { bluetoothManager },
            staleConnectionScheduler: { delay, watchdog in
                scheduledWatchdogs.append((delay, watchdog))
            },
            dateProvider: { now }
        )

        XCTAssertTrue(manager.scanForSensor())
        guard let sensor = bluetoothManager.delegate as? MicroTechSensor else {
            return XCTFail("Expected scan to install a MicroTechSensor delegate")
        }
        bluetoothManager.isConnected = true
        manager.microTechSensorDidConnect(sensor, session: makeSession(remoteIdentifier: remoteIdentifier))

        XCTAssertEqual(scheduledWatchdogs.count, 1)
        XCTAssertEqual(try XCTUnwrap(scheduledWatchdogs.first?.0), 15 * 60, accuracy: 0.001)

        now = now.addingTimeInterval(16 * 60)
        scheduledWatchdogs[0].1()

        XCTAssertEqual(bluetoothManager.disconnectCallCount, 1)
        XCTAssertEqual(bluetoothManager.scanRemoteIdentifiers, [remoteIdentifier, remoteIdentifier])
    }

    func testCurrentReadingRefreshesConnectedSensorWatchdog() throws {
        let remoteIdentifier = UUID(uuidString: "00000000-0000-0000-0000-000000000123")!
        var now = Date(timeIntervalSince1970: 1_700_000_000)
        var scheduledWatchdogs: [(TimeInterval, () -> Void)] = []
        var state = MicroTechCGMManagerState()
        state.remoteIdentifier = remoteIdentifier
        state.deviceName = "LinX-ABC123"
        state.sensorSerial = "ABC123"
        let bluetoothManager = FakeMicroTechBluetoothManager()
        let manager = MicroTechCGMManager(
            state: state,
            bluetoothManagerFactory: { bluetoothManager },
            staleConnectionScheduler: { delay, watchdog in
                scheduledWatchdogs.append((delay, watchdog))
            },
            dateProvider: { now }
        )

        XCTAssertTrue(manager.scanForSensor())
        guard let sensor = bluetoothManager.delegate as? MicroTechSensor else {
            return XCTFail("Expected scan to install a MicroTechSensor delegate")
        }
        bluetoothManager.isConnected = true
        manager.microTechSensorDidConnect(sensor, session: makeSession(remoteIdentifier: remoteIdentifier))
        now = now.addingTimeInterval(60)
        manager.microTechSensor(sensor, didRead: makeReading(sampleNumber: 42, glucoseMgdl: 123, receivedAt: now))

        XCTAssertEqual(scheduledWatchdogs.count, 2)
        now = Date(timeIntervalSince1970: 1_700_000_000 + 16 * 60)
        scheduledWatchdogs[0].1()

        XCTAssertEqual(bluetoothManager.disconnectCallCount, 0)

        now = now.addingTimeInterval(60)
        scheduledWatchdogs[1].1()

        XCTAssertEqual(bluetoothManager.disconnectCallCount, 1)
        XCTAssertEqual(bluetoothManager.scanRemoteIdentifiers, [remoteIdentifier, remoteIdentifier])
    }

    func testStaleWatchdogReconnectsAndLogsRecoveredCurrentReading() throws {
        let remoteIdentifier = UUID(uuidString: "00000000-0000-0000-0000-000000000123")!
        var now = Date(timeIntervalSince1970: 1_700_000_000)
        var scheduledWatchdogs: [(TimeInterval, () -> Void)] = []
        var state = MicroTechCGMManagerState()
        state.remoteIdentifier = remoteIdentifier
        state.deviceName = "LinX-ABC123"
        state.sensorSerial = "ABC123"
        let bluetoothManager = FakeMicroTechBluetoothManager()
        let manager = MicroTechCGMManager(
            state: state,
            bluetoothManagerFactory: { bluetoothManager },
            staleConnectionScheduler: { delay, watchdog in
                scheduledWatchdogs.append((delay, watchdog))
            },
            dateProvider: { now }
        )
        let delegate = TestCGMManagerDelegate(expectedReadingResultCount: 2)
        manager.delegateQueue = .main
        manager.cgmManagerDelegate = delegate

        XCTAssertTrue(manager.scanForSensor())
        guard let sensor = bluetoothManager.delegate as? MicroTechSensor else {
            return XCTFail("Expected scan to install a MicroTechSensor delegate")
        }
        bluetoothManager.isConnected = true
        manager.microTechSensorDidConnect(sensor, session: makeSession(remoteIdentifier: remoteIdentifier))

        now = now.addingTimeInterval(60)
        manager.microTechSensor(
            sensor,
            didRead: makeReading(sampleNumber: 42, glucoseMgdl: 123, receivedAt: now)
        )

        XCTAssertEqual(scheduledWatchdogs.count, 2)
        now = now.addingTimeInterval(16 * 60)
        scheduledWatchdogs[1].1()

        XCTAssertEqual(bluetoothManager.disconnectCallCount, 1)
        XCTAssertEqual(bluetoothManager.scanRemoteIdentifiers, [remoteIdentifier, remoteIdentifier])

        let reconnectedSensor = makeSensor(session: makeSession(remoteIdentifier: remoteIdentifier))
        bluetoothManager.isConnected = true
        now = now.addingTimeInterval(10)
        manager.registerSensorForTesting(reconnectedSensor)
        manager.microTechSensorDidConnect(reconnectedSensor, session: makeSession(remoteIdentifier: remoteIdentifier))
        manager.microTechSensor(
            reconnectedSensor,
            didRead: makeReading(sampleNumber: 43, glucoseMgdl: 124, receivedAt: now)
        )

        wait(for: [delegate.readingResultsExpectation], timeout: 1)
        XCTAssertEqual(delegate.newDataSampleSyncIdentifiers, ["ABC123-42", "ABC123-43"])
        XCTAssertTrue(delegate.loggedEvents.contains { event in
            event.type == .connection &&
                event.message.contains("disconnecting stale connection") &&
                event.message.contains("reason=stale reading")
        })
        XCTAssertTrue(delegate.loggedEvents.contains { event in
            event.type == .receive &&
                event.message.contains("current accepted serial=ABC123 sample=43") &&
                event.message.contains("recoveredAfterReconnect reason=stale reading")
        })
    }

    func testCurrentReadingWatchdogSchedulingDoesNotReadBluetoothConnectionState() throws {
        let remoteIdentifier = UUID(uuidString: "00000000-0000-0000-0000-000000000123")!
        var scheduledWatchdogs: [(TimeInterval, () -> Void)] = []
        var state = MicroTechCGMManagerState()
        state.remoteIdentifier = remoteIdentifier
        state.deviceName = "LinX-ABC123"
        state.sensorSerial = "ABC123"
        let bluetoothManager = FakeMicroTechBluetoothManager()
        let manager = MicroTechCGMManager(
            state: state,
            bluetoothManagerFactory: { bluetoothManager },
            staleConnectionScheduler: { delay, watchdog in
                scheduledWatchdogs.append((delay, watchdog))
            }
        )

        XCTAssertTrue(manager.scanForSensor())
        guard let sensor = bluetoothManager.delegate as? MicroTechSensor else {
            return XCTFail("Expected scan to install a MicroTechSensor delegate")
        }
        bluetoothManager.isConnected = true
        manager.microTechSensorDidConnect(sensor, session: makeSession(remoteIdentifier: remoteIdentifier))
        scheduledWatchdogs.removeAll()
        bluetoothManager.isConnectedReadCount = 0

        manager.microTechSensor(
            sensor,
            didRead: makeReading(
                sampleNumber: 42,
                glucoseMgdl: 123,
                receivedAt: Date(timeIntervalSince1970: 1_700_000_000)
            )
        )

        XCTAssertEqual(scheduledWatchdogs.count, 1)
        XCTAssertEqual(bluetoothManager.isConnectedReadCount, 0)
    }

    func testRestoredSavedSensorStartsScanWhenDelegateQueueIsConfigured() {
        let remoteIdentifier = UUID(uuidString: "00000000-0000-0000-0000-000000000123")!
        var state = MicroTechCGMManagerState()
        state.remoteIdentifier = remoteIdentifier
        state.deviceName = "LinX-ABC123"
        state.sensorSerial = "ABC123"
        let bluetoothManager = FakeMicroTechBluetoothManager()
        let manager = MicroTechCGMManager(
            state: state,
            bluetoothManagerFactory: { bluetoothManager },
            resumeScanWhenDelegateQueueConfigured: true
        )
        let delegate = TestCGMManagerDelegate(expectedReadingResultCount: 0)

        manager.cgmManagerDelegate = delegate
        manager.delegateQueue = .main

        XCTAssertEqual(bluetoothManager.scanRemoteIdentifiers, [remoteIdentifier])
        XCTAssertTrue(bluetoothManager.isScanning)
    }

    func testRestoredSavedSensorHandshakeEmitsRecoveredCurrentReadingAfterDelegateQueueResume() throws {
        let remoteIdentifier = UUID(uuidString: "00000000-0000-0000-0000-000000000123")!
        let material = MicroTechAidexKeyMaterial.derive(serial: "ABC123")
        let receivedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let currentPacket = try Data(microTechHexadecimalString: "030100FE60545F80B303800C4500004D5B")
        let encryptedCurrentPacket = try MicroTechAidexCrypto.encryptCfb128(
            key: material.key,
            iv: material.iv,
            plain: currentPacket
        )
        var state = MicroTechCGMManagerState()
        state.remoteIdentifier = remoteIdentifier
        state.deviceName = "LinX-ABC123"
        state.sensorSerial = "ABC123"
        state.hasConnectedSensorSession = true
        let bluetoothManager = FakeMicroTechBluetoothManager()
        let manager = MicroTechCGMManager(
            state: state,
            bluetoothManagerFactory: { bluetoothManager },
            resumeScanWhenDelegateQueueConfigured: true
        )
        let delegate = TestCGMManagerDelegate(expectedReadingResultCount: 1)

        manager.cgmManagerDelegate = delegate
        manager.delegateQueue = .main

        XCTAssertEqual(bluetoothManager.scanRemoteIdentifiers, [remoteIdentifier])
        guard let sensor = bluetoothManager.delegate as? MicroTechSensor else {
            return XCTFail("Expected restored scan to use a MicroTechSensor delegate")
        }
        let restoredPeripheral = FakeMicroTechPeripheralSession(
            deviceIdentifier: remoteIdentifier,
            deviceName: "LinX-ABC123",
            f002Challenge: try encryptedChallenge(for: material)
        )
        restoredPeripheral.onWrite = { value, characteristic in
            guard characteristic == MicroTechAidexProfile.f001UUID, value == material.key else {
                return
            }
            sensor.handleNotification(characteristic: MicroTechAidexProfile.f001UUID, value: material.key)
        }

        sensor.handleReadyPeripheralSession(restoredPeripheral)
        let deadline = Date(timeIntervalSinceNow: 1)
        while Date() < deadline,
              !restoredPeripheral.calls.contains(.subscribe(MicroTechAidexProfile.f003UUID.uuidString)) {
            Thread.sleep(forTimeInterval: 0.01)
        }
        sensor.handleNotification(
            characteristic: MicroTechAidexProfile.f003UUID,
            value: encryptedCurrentPacket,
            receivedAt: receivedAt
        )

        wait(for: [delegate.readingResultsExpectation], timeout: 1)
        XCTAssertEqual(delegate.newDataSampleSyncIdentifiers, ["ABC123-21600"])
        XCTAssertTrue(delegate.loggedEvents.contains { event in
            event.type == .connection &&
                event.message.contains("resume scan after delegate queue configured")
        })
        XCTAssertTrue(delegate.loggedEvents.contains { event in
            event.type == .receive &&
                event.message.contains("current accepted serial=ABC123 sample=21600") &&
                event.message.contains("recoveredAfterReconnect reason=delegate queue configured")
        })
    }

    func testSettingsViewModelScanUsesActualManagerScanningStateWhenConnected() {
        var state = MicroTechCGMManagerState()
        state.remoteIdentifier = UUID(uuidString: "00000000-0000-0000-0000-000000000123")!
        state.deviceName = "LinX-ABC123"
        state.sensorSerial = "ABC123"
        let bluetoothManager = FakeMicroTechBluetoothManager()
        bluetoothManager.isConnected = true
        let manager = MicroTechCGMManager(
            state: state,
            bluetoothManagerFactory: { bluetoothManager }
        )
        let viewModel = MicroTechSettingsViewModel(
            cgmManager: manager,
            displayGlucosePreference: DisplayGlucosePreference(displayGlucoseUnit: Self.mgdlUnit)
        )

        viewModel.scanForSensor()

        XCTAssertFalse(viewModel.isScanning)
        XCTAssertTrue(manager.isConnected)
        XCTAssertTrue(bluetoothManager.scanRemoteIdentifiers.isEmpty)
    }

    func testScanForSavedSensorRefreshesAlreadyConnectedBluetoothSession() {
        let remoteIdentifier = UUID(uuidString: "00000000-0000-0000-0000-000000000123")!
        var state = MicroTechCGMManagerState()
        state.remoteIdentifier = remoteIdentifier
        state.deviceName = "LinX-ABC123"
        state.sensorSerial = "ABC123"
        let bluetoothManager = FakeMicroTechBluetoothManager()
        bluetoothManager.isConnected = true
        let manager = MicroTechCGMManager(
            state: state,
            bluetoothManagerFactory: { bluetoothManager }
        )

        XCTAssertTrue(manager.scanForSensor())

        XCTAssertEqual(bluetoothManager.scanRemoteIdentifiers, [])
        XCTAssertEqual(bluetoothManager.refreshConnectedPeripheralCallCount, 1)
        XCTAssertTrue((bluetoothManager.delegate as AnyObject?) is MicroTechSensor)
    }

    func testSettingsViewModelStartsNearbyScanWithoutManualInput() {
        let bluetoothManager = FakeMicroTechBluetoothManager()
        let manager = MicroTechCGMManager(
            state: MicroTechCGMManagerState(),
            bluetoothManagerFactory: { bluetoothManager }
        )
        let viewModel = MicroTechSettingsViewModel(
            cgmManager: manager,
            displayGlucosePreference: DisplayGlucosePreference(displayGlucoseUnit: Self.mgdlUnit)
        )

        viewModel.scanForSensor()

        XCTAssertNil(viewModel.deviceName)
        XCTAssertNil(viewModel.sensorSerial)
        XCTAssertEqual(viewModel.scanButtonTitle, "Scan for Sensor")
        XCTAssertEqual(bluetoothManager.scanRemoteIdentifiers, [nil])
        XCTAssertTrue(viewModel.isScanning)
    }

    func testBluetoothFailureStoresVisibleConnectionErrorAndRefreshesSettingsViewModel() {
        let manager = MicroTechCGMManager()
        let viewModel = MicroTechSettingsViewModel(
            cgmManager: manager,
            displayGlucosePreference: DisplayGlucosePreference(displayGlucoseUnit: Self.mgdlUnit)
        )
        let refreshed = expectation(description: "settings view model refreshed")

        manager.recordBluetoothFailure(MicroTechCGMManagerTestError.poweredOff)

        DispatchQueue.main.async {
            XCTAssertEqual(manager.state.lastConnectionErrorDescription, "Bluetooth failed: poweredOff")
            XCTAssertEqual(viewModel.connectionErrorDescription, "Bluetooth failed: poweredOff")
            refreshed.fulfill()
        }
        wait(for: [refreshed], timeout: 1)
    }

    func testScanTimeoutRetriesSavedSensorWithoutClearingVisibleConnectionError() {
        let remoteIdentifier = UUID(uuidString: "00000000-0000-0000-0000-000000000123")!
        var state = MicroTechCGMManagerState()
        state.remoteIdentifier = remoteIdentifier
        state.deviceName = "LinX-ABC123"
        state.sensorSerial = "ABC123"
        let bluetoothManager = FakeMicroTechBluetoothManager()
        var retryBlocks: [() -> Void] = []
        let manager = MicroTechCGMManager(
            state: state,
            bluetoothManagerFactory: { bluetoothManager },
            bluetoothRetryScheduler: { retryBlocks.append($0) }
        )

        XCTAssertTrue(manager.scanForSensor())
        bluetoothManager.isScanning = false

        manager.recordBluetoothFailure(MicroTechBluetoothManagerError.scanTimeout(remoteIdentifier))

        XCTAssertEqual(bluetoothManager.scanRemoteIdentifiers, [remoteIdentifier])
        XCTAssertEqual(retryBlocks.count, 1)
        XCTAssertEqual(
            manager.state.lastConnectionErrorDescription,
            "Bluetooth failed: scan timed out for \(remoteIdentifier)"
        )
        guard retryBlocks.count == 1 else {
            return
        }

        retryBlocks[0]()

        XCTAssertEqual(bluetoothManager.scanRemoteIdentifiers, [remoteIdentifier, remoteIdentifier])
        XCTAssertTrue(bluetoothManager.isScanning)
    }

    func testSensorScanTimeoutRetriesSavedSensorWithoutSynchronousScan() {
        let remoteIdentifier = UUID(uuidString: "00000000-0000-0000-0000-000000000123")!
        var state = MicroTechCGMManagerState()
        state.remoteIdentifier = remoteIdentifier
        state.deviceName = "LinX-ABC123"
        state.sensorSerial = "ABC123"
        let bluetoothManager = FakeMicroTechBluetoothManager()
        var retryBlocks: [() -> Void] = []
        let manager = MicroTechCGMManager(
            state: state,
            bluetoothManagerFactory: { bluetoothManager },
            bluetoothRetryScheduler: { retryBlocks.append($0) }
        )

        XCTAssertTrue(manager.scanForSensor())
        guard let sensor = bluetoothManager.delegate as? MicroTechSensor else {
            return XCTFail("Expected scan to install a MicroTechSensor delegate")
        }
        bluetoothManager.isScanning = false

        manager.microTechSensor(sensor, didError: MicroTechBluetoothManagerError.scanTimeout(remoteIdentifier))

        XCTAssertEqual(bluetoothManager.scanRemoteIdentifiers, [remoteIdentifier])
        XCTAssertEqual(retryBlocks.count, 1)
        XCTAssertEqual(
            manager.state.lastConnectionErrorDescription,
            "Bluetooth failed: scan timed out for \(remoteIdentifier)"
        )

        retryBlocks[0]()

        XCTAssertEqual(bluetoothManager.scanRemoteIdentifiers, [remoteIdentifier, remoteIdentifier])
        XCTAssertTrue(bluetoothManager.isScanning)
    }

    func testRepeatedSavedIdentifierTimeoutsFallBackToNearbySerialScan() {
        let remoteIdentifier = UUID(uuidString: "00000000-0000-0000-0000-000000000123")!
        var state = MicroTechCGMManagerState()
        state.remoteIdentifier = remoteIdentifier
        state.deviceName = "LinX-ABC123"
        state.sensorSerial = "ABC123"
        let bluetoothManager = FakeMicroTechBluetoothManager()
        var retryBlocks: [() -> Void] = []
        let manager = MicroTechCGMManager(
            state: state,
            bluetoothManagerFactory: { bluetoothManager },
            bluetoothRetryScheduler: { retryBlocks.append($0) }
        )

        XCTAssertTrue(manager.scanForSensor())
        bluetoothManager.isScanning = false
        manager.recordBluetoothFailure(MicroTechBluetoothManagerError.scanTimeout(remoteIdentifier))
        retryBlocks.removeFirst()()
        bluetoothManager.isScanning = false

        manager.recordBluetoothFailure(MicroTechBluetoothManagerError.scanTimeout(remoteIdentifier))

        XCTAssertNil(manager.state.remoteIdentifier)
        XCTAssertEqual(retryBlocks.count, 1)
        retryBlocks.removeFirst()()
        XCTAssertEqual(bluetoothManager.scanRemoteIdentifiers, [remoteIdentifier, remoteIdentifier, nil])
        XCTAssertTrue(manager.shouldConnectToMicroTechDevice(deviceName: "LinX-ABC123", identifier: UUID()))
        XCTAssertFalse(manager.shouldConnectToMicroTechDevice(deviceName: "LinX-OTHER", identifier: UUID()))
    }

    func testRepeatedSavedIdentifierConnectionTimeoutsFallBackToNearbySerialScan() {
        let remoteIdentifier = UUID(uuidString: "00000000-0000-0000-0000-000000000123")!
        var state = MicroTechCGMManagerState()
        state.remoteIdentifier = remoteIdentifier
        state.deviceName = "LinX-ABC123"
        state.sensorSerial = "ABC123"
        let bluetoothManager = FakeMicroTechBluetoothManager()
        var retryBlocks: [() -> Void] = []
        let manager = MicroTechCGMManager(
            state: state,
            bluetoothManagerFactory: { bluetoothManager },
            bluetoothRetryScheduler: { retryBlocks.append($0) }
        )

        XCTAssertTrue(manager.scanForSensor())
        guard let sensor = bluetoothManager.delegate as? MicroTechSensor else {
            return XCTFail("Expected scan to install a MicroTechSensor delegate")
        }

        manager.microTechSensor(sensor, didError: MicroTechBluetoothManagerError.connectTimeout(remoteIdentifier))
        XCTAssertEqual(retryBlocks.count, 0)
        XCTAssertEqual(bluetoothManager.scanRemoteIdentifiers, [remoteIdentifier])

        manager.microTechSensor(sensor, didError: MicroTechBluetoothManagerError.connectTimeout(remoteIdentifier))

        XCTAssertNil(manager.state.remoteIdentifier)
        XCTAssertEqual(bluetoothManager.disconnectCallCount, 1)
        XCTAssertEqual(retryBlocks.count, 1)
        retryBlocks.removeFirst()()
        XCTAssertEqual(bluetoothManager.scanRemoteIdentifiers, [remoteIdentifier, nil])
        XCTAssertTrue(manager.shouldConnectToMicroTechDevice(deviceName: "LinX-ABC123", identifier: UUID()))
        XCTAssertFalse(manager.shouldConnectToMicroTechDevice(deviceName: "LinX-OTHER", identifier: UUID()))
    }

    func testRepeatedSavedIdentifierConfigurationTimeoutsFallBackToNearbySerialScan() {
        let remoteIdentifier = UUID(uuidString: "00000000-0000-0000-0000-000000000123")!
        var state = MicroTechCGMManagerState()
        state.remoteIdentifier = remoteIdentifier
        state.deviceName = "LinX-ABC123"
        state.sensorSerial = "ABC123"
        let bluetoothManager = FakeMicroTechBluetoothManager()
        var retryBlocks: [() -> Void] = []
        let manager = MicroTechCGMManager(
            state: state,
            bluetoothManagerFactory: { bluetoothManager },
            bluetoothRetryScheduler: { retryBlocks.append($0) }
        )

        XCTAssertTrue(manager.scanForSensor())
        guard let sensor = bluetoothManager.delegate as? MicroTechSensor else {
            return XCTFail("Expected scan to install a MicroTechSensor delegate")
        }

        manager.microTechSensor(sensor, didError: MicroTechBluetoothManagerError.configureTimeout(remoteIdentifier))
        XCTAssertEqual(retryBlocks.count, 0)
        XCTAssertEqual(bluetoothManager.scanRemoteIdentifiers, [remoteIdentifier])

        manager.microTechSensor(sensor, didError: MicroTechBluetoothManagerError.configureTimeout(remoteIdentifier))

        XCTAssertNil(manager.state.remoteIdentifier)
        XCTAssertEqual(bluetoothManager.disconnectCallCount, 1)
        XCTAssertEqual(retryBlocks.count, 1)
        retryBlocks.removeFirst()()
        XCTAssertEqual(bluetoothManager.scanRemoteIdentifiers, [remoteIdentifier, nil])
        XCTAssertTrue(manager.shouldConnectToMicroTechDevice(deviceName: "LinX-ABC123", identifier: UUID()))
        XCTAssertFalse(manager.shouldConnectToMicroTechDevice(deviceName: "LinX-OTHER", identifier: UUID()))
    }

    func testRepeatedSavedIdentifierConnectionFailuresFallBackToNearbySerialScan() {
        let remoteIdentifier = UUID(uuidString: "00000000-0000-0000-0000-000000000123")!
        var state = MicroTechCGMManagerState()
        state.remoteIdentifier = remoteIdentifier
        state.deviceName = "LinX-ABC123"
        state.sensorSerial = "ABC123"
        let bluetoothManager = FakeMicroTechBluetoothManager()
        var retryBlocks: [() -> Void] = []
        let manager = MicroTechCGMManager(
            state: state,
            bluetoothManagerFactory: { bluetoothManager },
            bluetoothRetryScheduler: { retryBlocks.append($0) }
        )

        XCTAssertTrue(manager.scanForSensor())
        guard let sensor = bluetoothManager.delegate as? MicroTechSensor else {
            return XCTFail("Expected scan to install a MicroTechSensor delegate")
        }

        manager.microTechSensor(sensor, didError: MicroTechBluetoothManagerError.connectFailed(remoteIdentifier, "peripheral disconnected"))
        XCTAssertEqual(retryBlocks.count, 0)
        manager.microTechSensor(sensor, didError: MicroTechBluetoothManagerError.connectFailed(remoteIdentifier, "peripheral disconnected"))

        XCTAssertNil(manager.state.remoteIdentifier)
        XCTAssertEqual(bluetoothManager.disconnectCallCount, 1)
        XCTAssertEqual(retryBlocks.count, 1)
        retryBlocks.removeFirst()()
        XCTAssertEqual(bluetoothManager.scanRemoteIdentifiers, [remoteIdentifier, nil])
    }

    func testSettingsViewModelScanClearsPreviousConnectionError() {
        var state = MicroTechCGMManagerState()
        state.lastConnectionErrorDescription = "Bluetooth failed: poweredOff"
        let bluetoothManager = FakeMicroTechBluetoothManager()
        let manager = MicroTechCGMManager(
            state: state,
            bluetoothManagerFactory: { bluetoothManager }
        )
        let viewModel = MicroTechSettingsViewModel(
            cgmManager: manager,
            displayGlucosePreference: DisplayGlucosePreference(displayGlucoseUnit: Self.mgdlUnit)
        )

        XCTAssertEqual(viewModel.connectionErrorDescription, "Bluetooth failed: poweredOff")

        viewModel.scanForSensor()

        XCTAssertNil(manager.state.lastConnectionErrorDescription)
        XCTAssertNil(viewModel.connectionErrorDescription)
        XCTAssertEqual(bluetoothManager.scanRemoteIdentifiers, [nil])
    }

    func testSetupOnboardsOnlyAfterNearbySensorConnection() {
        let bluetoothManager = FakeMicroTechBluetoothManager()
        let manager = MicroTechCGMManager(
            state: MicroTechCGMManagerState(),
            bluetoothManagerFactory: { bluetoothManager }
        )
        let onboardingDelegate = TestCGMOnboardingDelegate(expectedCreateCount: 1, expectedOnboardCount: 1)
        let coordinator = MicroTechUICoordinator(
            colorPalette: EnvironmentValues().colorPalette,
            displayGlucosePreference: DisplayGlucosePreference(displayGlucoseUnit: Self.mgdlUnit),
            allowDebugFeatures: false,
            makeCGMManager: { manager }
        )
        coordinator.cgmManagerOnboardingDelegate = onboardingDelegate

        coordinator.completeSetup()

        XCTAssertEqual(bluetoothManager.scanRemoteIdentifiers, [nil])
        XCTAssertTrue(onboardingDelegate.createdManagers.isEmpty)
        XCTAssertTrue(onboardingDelegate.onboardedManagers.isEmpty)

        let session = makeSession()
        let sensor = makeSensor(session: session)
        manager.registerSensorForTesting(sensor)
        manager.microTechSensorDidConnect(sensor, session: session)

        wait(for: [onboardingDelegate.createdExpectation, onboardingDelegate.onboardedExpectation], timeout: 1)
        XCTAssertTrue(onboardingDelegate.createdManagers.first === manager)
        XCTAssertTrue(onboardingDelegate.onboardedManagers.first === manager)
    }

    func testSetupDoesNotOnboardWhenNearbyDeviceIsSavedBeforeHandshake() throws {
        let bluetoothManager = FakeMicroTechBluetoothManager()
        let manager = MicroTechCGMManager(
            state: MicroTechCGMManagerState(),
            bluetoothManagerFactory: { bluetoothManager }
        )
        let onboardingDelegate = TestCGMOnboardingDelegate(expectedCreateCount: 0, expectedOnboardCount: 0)
        let coordinator = MicroTechUICoordinator(
            colorPalette: EnvironmentValues().colorPalette,
            displayGlucosePreference: DisplayGlucosePreference(displayGlucoseUnit: Self.mgdlUnit),
            allowDebugFeatures: false,
            makeCGMManager: { manager }
        )
        coordinator.cgmManagerOnboardingDelegate = onboardingDelegate
        let material = MicroTechAidexKeyMaterial.derive(serial: "NEARBY123")
        let peripheralSession = FakeMicroTechPeripheralSession(
            deviceIdentifier: UUID(uuidString: "00000000-0000-0000-0000-000000000321")!,
            deviceName: "LinX-NEARBY123",
            f002Challenge: try encryptedChallenge(for: material),
            failurePoint: .read,
            subscriptionFailures: [MicroTechAidexProfile.f001UUID]
        )

        coordinator.completeSetup()
        manager.connectDiscoveredSensor(peripheralSession: peripheralSession)

        wait(for: [onboardingDelegate.createdExpectation, onboardingDelegate.onboardedExpectation], timeout: 0.2)
        XCTAssertEqual(manager.state.sensorSerial, "NEARBY123")
        XCTAssertFalse(manager.cgmManagerStatus.hasValidSensorSession)
        XCTAssertTrue(onboardingDelegate.createdManagers.isEmpty)
        XCTAssertTrue(onboardingDelegate.onboardedManagers.isEmpty)
    }

    func testSettingsViewModelRefreshDisplaysManagerStateAndWritesUploadPreference() {
        let noSensorViewModel = MicroTechSettingsViewModel(
            cgmManager: MicroTechCGMManager(),
            displayGlucosePreference: DisplayGlucosePreference(displayGlucoseUnit: Self.mgdlUnit)
        )
        XCTAssertEqual(noSensorViewModel.scanButtonTitle, "Scan for Sensor")

        let readingDate = Date(timeIntervalSince1970: 1_700_000_000)
        let reading = makeReading(sampleNumber: 42, glucoseMgdl: 123, receivedAt: readingDate)
        var state = MicroTechCGMManagerState()
        state.deviceName = "LinX-ABC123"
        state.sensorSerial = "ABC123"
        state.lastReadingDate = readingDate
        state.latestReading = reading
        state.latestSampleNumber = 42
        state.uploadReadings = true
        let manager = MicroTechCGMManager(state: state)
        let displayGlucosePreference = DisplayGlucosePreference(displayGlucoseUnit: Self.mgdlUnit)
        let viewModel = MicroTechSettingsViewModel(
            cgmManager: manager,
            displayGlucosePreference: displayGlucosePreference
        )

        XCTAssertEqual(viewModel.deviceName, "LinX-ABC123")
        XCTAssertEqual(viewModel.sensorSerial, "ABC123")
        XCTAssertEqual(viewModel.lastReadingDate, readingDate)
        XCTAssertEqual(viewModel.lastGlucoseString, displayGlucosePreference.formatter.string(from: reading.glucoseQuantity!))
        XCTAssertTrue(viewModel.uploadReadings)
        XCTAssertEqual(viewModel.scanButtonTitle, "Scan for Sensor")

        viewModel.uploadReadings = false
        XCTAssertFalse(manager.state.uploadReadings)

        let refreshedDate = Date(timeIntervalSince1970: 1_700_000_300)
        let refreshedReading = makeReading(sampleNumber: 43, glucoseMgdl: 124, receivedAt: refreshedDate)
        _ = manager.accept(refreshedReading)
        viewModel.refresh()

        XCTAssertEqual(viewModel.lastReadingDate, refreshedDate)
        XCTAssertEqual(viewModel.lastGlucoseString, displayGlucosePreference.formatter.string(from: refreshedReading.glucoseQuantity!))
        XCTAssertFalse(viewModel.uploadReadings)
    }

    func testSensorConnectAndCurrentReadUpdateStateAndEmitNewData() throws {
        let manager = MicroTechCGMManager()
        let delegate = TestCGMManagerDelegate(expectedReadingResultCount: 1)
        manager.delegateQueue = .main
        manager.cgmManagerDelegate = delegate
        let session = makeSession()
        let sensor = makeSensor(session: session)
        let readingDate = Date(timeIntervalSince1970: 1_700_000_000)

        manager.registerSensorForTesting(sensor)

        manager.microTechSensorDidConnect(sensor, session: session)
        manager.microTechSensor(sensor, didRead: makeReading(sampleNumber: 42, glucoseMgdl: 123, receivedAt: readingDate))

        wait(for: [delegate.readingResultsExpectation], timeout: 1)
        XCTAssertEqual(manager.state.sensorSerial, "ABC123")
        XCTAssertEqual(manager.state.deviceName, "LinX-ABC123")
        XCTAssertEqual(manager.state.latestSampleNumber, 42)
        XCTAssertEqual(delegate.newDataSampleSyncIdentifiers, ["ABC123-42"])
    }

    func testManagerAcceptedReadingLogsCompleteRawPacket() throws {
        let manager = MicroTechCGMManager()
        let delegate = TestCGMManagerDelegate(expectedReadingResultCount: 1)
        manager.delegateQueue = .main
        manager.cgmManagerDelegate = delegate
        let session = makeSession()
        let sensor = makeSensor(session: session)
        let rawPacket = Data((0..<48).map(UInt8.init))
        let readingDate = Date(timeIntervalSince1970: 1_700_000_000)

        manager.registerSensorForTesting(sensor)

        manager.microTechSensorDidConnect(sensor, session: session)
        manager.microTechSensor(
            sensor,
            didRead: makeReading(
                sampleNumber: 42,
                glucoseMgdl: 123,
                receivedAt: readingDate,
                rawBytes: rawPacket
            )
        )

        wait(for: [delegate.readingResultsExpectation], timeout: 1)
        let acceptedLog = try XCTUnwrap(delegate.loggedEvents.first { event in
            event.type == .receive && event.message.contains("current accepted serial=ABC123 sample=42")
        })
        XCTAssertTrue(acceptedLog.message.contains("rawHex=\(rawPacket.microTechHexadecimalString)"))
        XCTAssertFalse(acceptedLog.message.contains("rawPrefix"))
        XCTAssertFalse(acceptedLog.message.contains("hexPrefix"))
        XCTAssertFalse(acceptedLog.message.contains("..."))
    }

    func testManagerRejectedReadingLogsCompleteRawPacket() throws {
        let manager = MicroTechCGMManager()
        let delegate = TestCGMManagerDelegate(expectedReadingResultCount: 2)
        manager.delegateQueue = .main
        manager.cgmManagerDelegate = delegate
        let session = makeSession()
        let sensor = makeSensor(session: session)
        let acceptedPacket = Data((0..<40).map(UInt8.init))
        let rejectedPacket = Data((40..<88).map(UInt8.init))
        let readingDate = Date(timeIntervalSince1970: 1_700_000_000)

        manager.registerSensorForTesting(sensor)

        manager.microTechSensorDidConnect(sensor, session: session)
        manager.microTechSensor(
            sensor,
            didRead: makeReading(
                sampleNumber: 42,
                glucoseMgdl: 123,
                receivedAt: readingDate,
                rawBytes: acceptedPacket
            )
        )
        manager.microTechSensor(
            sensor,
            didRead: makeReading(
                sampleNumber: 42,
                glucoseMgdl: 123,
                receivedAt: readingDate.addingTimeInterval(60),
                rawBytes: rejectedPacket
            )
        )

        wait(for: [delegate.readingResultsExpectation], timeout: 1)
        let rejectedLog = try XCTUnwrap(delegate.loggedEvents.first { event in
            event.type == .receive &&
                event.message.contains("current rejected serial=ABC123 sample=42") &&
                event.message.contains("reason=duplicateOrOld")
        })
        XCTAssertTrue(rejectedLog.message.contains("rawHex=\(rejectedPacket.microTechHexadecimalString)"))
        XCTAssertFalse(rejectedLog.message.contains("rawPrefix"))
        XCTAssertFalse(rejectedLog.message.contains("..."))
    }

    func testLinxF003CurrentNotificationFromDeviceLogEmitsNewDataAndDiagnosticLogs() throws {
        let manager = MicroTechCGMManager()
        let delegate = TestCGMManagerDelegate(expectedReadingResultCount: 1)
        manager.delegateQueue = .main
        manager.cgmManagerDelegate = delegate
        let material = MicroTechAidexKeyMaterial.derive(serial: "ABC123")
        let plain = try Data(microTechHexadecimalString: "030100FE60545F80B303800C4500004D5B")
        let encrypted = try MicroTechAidexCrypto.encryptCfb128(key: material.key, iv: material.iv, plain: plain)
        let receivedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let remoteIdentifier = UUID(uuidString: "00000000-0000-0000-0000-000000000123")!
        let fake = FakeMicroTechPeripheralSession(
            deviceIdentifier: remoteIdentifier,
            deviceName: "LinX-ABC123",
            f002Challenge: try encryptedChallenge(for: material)
        )
        let sensor = MicroTechSensor(
            session: MicroTechAidexSession(
                remoteIdentifier: remoteIdentifier,
                deviceName: "LinX-ABC123",
                sensorSerial: "ABC123"
            ),
            peripheralSession: fake,
            pairingKeyTimeout: 0
        )
        sensor.delegate = manager
        manager.registerSensorForTesting(sensor)

        try sensor.start()
        sensor.handleNotification(
            characteristic: MicroTechAidexProfile.f003UUID,
            value: encrypted,
            receivedAt: receivedAt
        )

        wait(for: [delegate.readingResultsExpectation], timeout: 1)
        XCTAssertEqual(delegate.newDataSampleSyncIdentifiers, ["ABC123-21600"])
        XCTAssertEqual(delegate.newDataSamples.map { Int($0.quantity.doubleValue(for: Self.mgdlUnit)) }, [95])
        XCTAssertEqual(manager.state.latestSampleNumber, 21600)
        XCTAssertEqual(manager.state.latestReading?.trend, -2)
        XCTAssertTrue(delegate.loggedEvents.contains { event in
            event.type == .receive &&
                event.message.contains("stage=packet event=decrypted characteristic=F003") &&
                event.message.contains("plainHex=030100FE60545F80B303800C4500004D5B")
        })
        XCTAssertTrue(delegate.loggedEvents.contains { event in
            event.type == .receive &&
                event.message.contains("parsed current packetType=0x03") &&
                event.message.contains("sample=21600") &&
                event.message.contains("rawHex=030100FE60545F80B303800C4500004D5B")
        })
        XCTAssertTrue(delegate.loggedEvents.contains { event in
            event.type == .receive &&
                event.message.contains("current accepted serial=ABC123 sample=21600") &&
                event.message.contains("packetType=0x03") &&
                event.message.contains("rawHex=030100FE60545F80B303800C4500004D5B")
        })
    }

    func testStatusObserverReceivesSensorSessionAndReadingUpdates() throws {
        let manager = MicroTechCGMManager()
        let observer = TestCGMStatusObserver(expectedStatusCount: 2)
        let statusQueue = DispatchQueue(label: "MicroTechCGMManagerTests.statusObserver")
        let session = makeSession()
        let sensor = makeSensor(session: session)

        manager.addStatusObserver(observer, queue: statusQueue)
        manager.registerSensorForTesting(sensor)
        manager.microTechSensorDidConnect(sensor, session: session)
        manager.microTechSensor(
            sensor,
            didRead: makeReading(
                sampleNumber: 42,
                glucoseMgdl: 123,
                receivedAt: Date(timeIntervalSince1970: 1_700_000_000)
            )
        )

        wait(for: [observer.statusExpectation], timeout: 1)
        statusQueue.sync {}
        XCTAssertEqual(observer.statuses.map(\.hasValidSensorSession), [true, true])
        XCTAssertEqual(observer.statuses.last?.lastCommunicationDate, Date(timeIntervalSince1970: 1_700_000_000))
    }

    func testRemovingStatusObserverStopsMicroTechStatusUpdates() throws {
        let manager = MicroTechCGMManager()
        let observer = TestCGMStatusObserver(expectedStatusCount: 0)
        let statusQueue = DispatchQueue(label: "MicroTechCGMManagerTests.removedStatusObserver")
        let session = makeSession()
        let sensor = makeSensor(session: session)

        manager.addStatusObserver(observer, queue: statusQueue)
        manager.removeStatusObserver(observer)
        manager.registerSensorForTesting(sensor)
        manager.microTechSensorDidConnect(sensor, session: session)

        wait(for: [observer.statusExpectation], timeout: 0.2)
        statusQueue.sync {}
        XCTAssertTrue(observer.statuses.isEmpty)
    }

    func testSensorCurrentReadUsesDelegateStartDateFilter() throws {
        let manager = MicroTechCGMManager()
        let delegate = TestCGMManagerDelegate(expectedReadingResultCount: 1)
        let delegateQueue = DispatchQueue(label: "MicroTechCGMManagerTests.startDateFilter")
        let readingDate = Date(timeIntervalSince1970: 1_700_000_000)
        delegate.startDateForFiltering = readingDate.addingTimeInterval(60)
        manager.delegateQueue = delegateQueue
        manager.cgmManagerDelegate = delegate
        let session = makeSession()
        let sensor = makeSensor(session: session)

        manager.registerSensorForTesting(sensor)
        manager.microTechSensorDidConnect(sensor, session: session)
        manager.microTechSensor(sensor, didRead: makeReading(sampleNumber: 42, glucoseMgdl: 123, receivedAt: readingDate))

        wait(for: [delegate.readingResultsExpectation], timeout: 1)
        XCTAssertEqual(delegate.noDataCount, 1)
        XCTAssertNil(manager.state.latestSampleNumber)
        XCTAssertNil(manager.state.latestReading)
        XCTAssertTrue(delegate.loggedEvents.contains { event in
            event.type == .receive && event.message.contains("reason=beforeStartDate")
        })
    }

    func testSensorErrorsAreLoggedWithReadableNames() throws {
        let manager = MicroTechCGMManager()
        let delegate = TestCGMManagerDelegate(expectedReadingResultCount: 1)
        manager.delegateQueue = .main
        manager.cgmManagerDelegate = delegate
        let session = makeSession()
        let sensor = makeSensor(session: session)

        manager.registerSensorForTesting(sensor)

        manager.microTechSensorDidConnect(sensor, session: session)
        manager.microTechSensor(sensor, didError: MicroTechAidexParserError.unsupportedPacket(0x04))

        wait(for: [delegate.readingResultsExpectation], timeout: 1)
        XCTAssertTrue(delegate.loggedEvents.contains { event in
            event.type == .error && event.message.contains("unsupportedPacket(4)")
        })
        XCTAssertFalse(delegate.loggedEvents.contains { event in
            event.message.contains("ParserError error")
        })
    }

    func testIgnoredStatusPacketIsLoggedWithoutReadingError() throws {
        let manager = MicroTechCGMManager()
        let delegate = TestCGMManagerDelegate(expectedReadingResultCount: 0)
        manager.delegateQueue = .main
        manager.cgmManagerDelegate = delegate
        let session = makeSession()
        let sensor = makeSensor(session: session)
        let rawPacket = Data((0..<48).map(UInt8.init))

        manager.registerSensorForTesting(sensor)

        manager.microTechSensorDidConnect(sensor, session: session)
        manager.microTechSensor(
            sensor,
            didIgnorePacketType: 0x04,
            length: rawPacket.count,
            hexPrefix: rawPacket.microTechHexadecimalString
        )

        wait(for: [delegate.readingResultsExpectation], timeout: 0.1)
        let ignoredLog = try XCTUnwrap(delegate.loggedEvents.first { event in
            event.type == .receive && event.message.contains("ignored unsupported packet type 0x04")
        })
        XCTAssertTrue(ignoredLog.message.contains("len=48 rawHex=\(rawPacket.microTechHexadecimalString)"))
        XCTAssertFalse(ignoredLog.message.contains("rawPrefix"))
        XCTAssertFalse(ignoredLog.message.contains("..."))
        XCTAssertFalse(delegate.loggedEvents.contains { event in
            event.type == .error && event.message.contains("unsupportedPacket(4)")
        })
        XCTAssertNil(manager.state.lastConnectionErrorDescription)
    }

    func testRepeatedSensorErrorsDisconnectToRestartBluetooth() throws {
        let remoteIdentifier = UUID(uuidString: "00000000-0000-0000-0000-000000000123")!
        var state = MicroTechCGMManagerState()
        state.remoteIdentifier = remoteIdentifier
        state.deviceName = "LinX-ABC123"
        state.sensorSerial = "ABC123"
        let bluetoothManager = FakeMicroTechBluetoothManager()
        bluetoothManager.isConnected = true
        var retryBlocks: [() -> Void] = []
        var recoveryBlocks: [(TimeInterval, () -> Void)] = []
        let manager = MicroTechCGMManager(
            state: state,
            bluetoothManagerFactory: { bluetoothManager },
            bluetoothRetryScheduler: { retryBlocks.append($0) },
            reconnectRecoveryScheduler: { recoveryBlocks.append(($0, $1)) }
        )
        let delegate = TestCGMManagerDelegate(expectedReadingResultCount: 3)
        let viewModel = MicroTechSettingsViewModel(
            cgmManager: manager,
            displayGlucosePreference: DisplayGlucosePreference(displayGlucoseUnit: Self.mgdlUnit)
        )
        manager.delegateQueue = .main
        manager.cgmManagerDelegate = delegate

        XCTAssertTrue(manager.scanForSensor())
        guard let sensor = bluetoothManager.delegate as? MicroTechSensor else {
            return XCTFail("Expected scan to install a MicroTechSensor delegate")
        }
        manager.microTechSensorDidConnect(sensor, session: makeSession(remoteIdentifier: remoteIdentifier))

        manager.microTechSensor(sensor, didError: MicroTechAidexParserError.invalidCRC)
        manager.microTechSensor(sensor, didError: MicroTechAidexParserError.invalidCRC)
        manager.microTechSensor(sensor, didError: MicroTechAidexParserError.invalidCRC)

        wait(for: [delegate.readingResultsExpectation], timeout: 1)
        XCTAssertEqual(bluetoothManager.disconnectCallCount, 1)
        XCTAssertEqual(bluetoothManager.scanRemoteIdentifiers, [])
        XCTAssertEqual(retryBlocks.count, 1)
        XCTAssertEqual(recoveryBlocks.count, 1)
        XCTAssertEqual(try XCTUnwrap(recoveryBlocks.first?.0), 60, accuracy: 0.001)
        XCTAssertEqual(manager.reconnectRecoveryPhaseForTesting, "timing")
        XCTAssertEqual(manager.state.lastConnectionErrorDescription, "Sensor error: invalidCRC")
        XCTAssertEqual(viewModel.connectionErrorDescription, "Sensor error: invalidCRC")
        XCTAssertTrue(delegate.loggedEvents.contains { event in
            event.type == .connection &&
                event.message.contains("restarting connection after 3 consecutive sensor errors")
        })
        guard retryBlocks.count == 1 else {
            return
        }

        retryBlocks[0]()

        XCTAssertEqual(bluetoothManager.scanRemoteIdentifiers, [remoteIdentifier])
    }

    func testBluetoothManagerErrorsHaveReadableDescriptions() {
        let remoteIdentifier = UUID(uuidString: "00000000-0000-0000-0000-000000000123")!

        XCTAssertEqual(
            String(describing: MicroTechBluetoothManagerError.connectTimeout(remoteIdentifier)),
            "connection timed out for \(remoteIdentifier)"
        )
        XCTAssertEqual(
            String(describing: MicroTechBluetoothManagerError.connectFailed(remoteIdentifier, "peripheral disconnected")),
            "connection failed for \(remoteIdentifier): peripheral disconnected"
        )
        XCTAssertEqual(
            String(describing: MicroTechBluetoothManagerError.configureTimeout(remoteIdentifier)),
            "configuration timed out for \(remoteIdentifier)"
        )
        XCTAssertEqual(
            String(describing: MicroTechBluetoothManagerError.scanTimeout(remoteIdentifier)),
            "scan timed out for \(remoteIdentifier)"
        )
        XCTAssertEqual(
            String(describing: MicroTechBluetoothManagerError.bluetoothUnavailable(4)),
            "Bluetooth unavailable state=4"
        )
    }

    func testCurrentReadRequestsHistoryBackfillFromWarmupIndex() throws {
        let manager = MicroTechCGMManager()
        let delegate = TestCGMManagerDelegate(expectedReadingResultCount: 1)
        manager.delegateQueue = .main
        manager.cgmManagerDelegate = delegate
        let session = makeSession()
        let material = MicroTechAidexKeyMaterial.derive(serial: session.sensorSerial)
        let peripheralSession = FakeMicroTechPeripheralSession(
            deviceIdentifier: session.remoteIdentifier,
            deviceName: session.deviceName,
            f002Challenge: try encryptedChallenge(for: material)
        )
        let sensor = MicroTechSensor(session: session, peripheralSession: peripheralSession, pairingKeyTimeout: 0)
        sensor.delegate = manager
        manager.registerSensorForTesting(sensor)
        try sensor.start()

        manager.microTechSensor(
            sensor,
            didRead: makeReading(
                sampleNumber: 65,
                glucoseMgdl: 123,
                receivedAt: Date(timeIntervalSince1970: 1_700_000_000)
            )
        )

        wait(for: [delegate.readingResultsExpectation], timeout: 1)
        let expectedHistoryCommand = try MicroTechAidexCommandBuilder(keyMaterial: material)
            .cmd23(index: 60)
            .microTechHexadecimalString
        let historyWrite = FakeMicroTechPeripheralSession.Call.write(
            expectedHistoryCommand,
            MicroTechAidexProfile.f002UUID.uuidString
        )
        let deadline = Date(timeIntervalSinceNow: 1)
        while Date() < deadline, !peripheralSession.calls.contains(historyWrite) {
            Thread.sleep(forTimeInterval: 0.01)
        }
        XCTAssertTrue(peripheralSession.calls.contains(historyWrite))
        XCTAssertTrue(delegate.loggedEvents.contains { event in
            event.type == .send && event.message.contains("history backfill requested from=60 current=65")
        })
    }

    func testSensorHistoryReadEmitsNewGlucoseSamplesWithoutChangingLatestSampleNumber() throws {
        let manager = MicroTechCGMManager()
        let delegate = TestCGMManagerDelegate(expectedReadingResultCount: 2)
        manager.delegateQueue = .main
        manager.cgmManagerDelegate = delegate
        let session = makeSession()
        let sensor = makeSensor(session: session)

        manager.registerSensorForTesting(sensor)

        manager.microTechSensorDidConnect(sensor, session: session)
        manager.microTechSensor(
            sensor,
            didRead: makeReading(
                sampleNumber: 42,
                glucoseMgdl: 123,
                receivedAt: Date(timeIntervalSince1970: 1_700_000_000)
            )
        )
        manager.microTechSensor(
            sensor,
            didReadHistory: MicroTechAidexHistoryPacket(
                rawBytes: Data([0x02]),
                startTimeOffset: 42,
                records: [
                    MicroTechAidexHistoryRecord(
                        timeOffset: 41,
                        glucose: 122,
                        rawValue: 122
                    ),
                ]
            )
        )

        wait(for: [delegate.readingResultsExpectation], timeout: 1)
        XCTAssertEqual(manager.state.latestSampleNumber, 42)
        XCTAssertEqual(delegate.newDataSampleSyncIdentifiers, ["ABC123-42", "ABC123-41"])
        XCTAssertEqual(delegate.newDataSamples.map { Int($0.quantity.doubleValue(for: Self.mgdlUnit)) }, [123, 122])
        XCTAssertEqual(delegate.noDataCount, 0)
        XCTAssertTrue(delegate.loggedEvents.contains { event in
            event.type == .receive && event.message.contains("current accepted serial=ABC123 sample=42")
        })
        XCTAssertTrue(delegate.loggedEvents.contains { event in
            event.type == .receive && event.message.contains("history processed serial=ABC123 records=1 accepted=1")
        })
        XCTAssertTrue(delegate.loggedEvents.contains { event in
            event.type == .receive && event.message.contains("anchor=current")
        })
    }

    func testSensorHistoryReadHandlesSampleNumberRollover() throws {
        let manager = MicroTechCGMManager()
        let delegate = TestCGMManagerDelegate(expectedReadingResultCount: 2)
        manager.delegateQueue = .main
        manager.cgmManagerDelegate = delegate
        let session = makeSession()
        let sensor = makeSensor(session: session)
        let currentDate = Date(timeIntervalSince1970: 1_700_000_000)

        manager.registerSensorForTesting(sensor)

        manager.microTechSensorDidConnect(sensor, session: session)
        manager.microTechSensor(
            sensor,
            didRead: makeReading(
                sampleNumber: 2,
                glucoseMgdl: 123,
                receivedAt: currentDate
            )
        )
        manager.microTechSensor(
            sensor,
            didReadHistory: MicroTechAidexHistoryPacket(
                rawBytes: Data([0x23]),
                startTimeOffset: 65535,
                records: [
                    MicroTechAidexHistoryRecord(timeOffset: 65535, glucose: 120, rawValue: 120),
                    MicroTechAidexHistoryRecord(timeOffset: 1, glucose: 122, rawValue: 122),
                    MicroTechAidexHistoryRecord(timeOffset: 3, glucose: 124, rawValue: 124),
                ]
            )
        )

        wait(for: [delegate.readingResultsExpectation], timeout: 1)
        XCTAssertEqual(delegate.newDataSampleSyncIdentifiers, ["ABC123-2", "ABC123-65535", "ABC123-1"])
        XCTAssertEqual(delegate.newDataSamples.map(\.date), [
            currentDate,
            currentDate.addingTimeInterval(-3 * 60),
            currentDate.addingTimeInterval(-1 * 60),
        ])
        XCTAssertTrue(delegate.loggedEvents.contains { event in
            event.type == .receive && event.message.contains("accepted=2") && event.message.contains("tooNew=1")
        })
    }

    func testSensorHistoryReadAcceptsSampleZeroAcrossRollover() throws {
        let manager = MicroTechCGMManager()
        let delegate = TestCGMManagerDelegate(expectedReadingResultCount: 2)
        manager.delegateQueue = .main
        manager.cgmManagerDelegate = delegate
        let session = makeSession()
        let sensor = makeSensor(session: session)
        let currentDate = Date(timeIntervalSince1970: 1_700_000_120)

        manager.registerSensorForTesting(sensor)

        manager.microTechSensorDidConnect(sensor, session: session)
        manager.microTechSensor(
            sensor,
            didRead: makeReading(
                sampleNumber: 1,
                glucoseMgdl: 124,
                receivedAt: currentDate
            )
        )
        manager.microTechSensor(
            sensor,
            didReadHistory: MicroTechAidexHistoryPacket(
                rawBytes: Data([0x23]),
                startTimeOffset: 65535,
                records: [
                    MicroTechAidexHistoryRecord(timeOffset: 65535, glucose: 120, rawValue: 120),
                    MicroTechAidexHistoryRecord(timeOffset: 0, glucose: 122, rawValue: 122),
                ]
            )
        )

        wait(for: [delegate.readingResultsExpectation], timeout: 1)
        XCTAssertEqual(delegate.newDataSampleSyncIdentifiers, ["ABC123-1", "ABC123-65535", "ABC123-0"])
        XCTAssertEqual(delegate.newDataSamples.map(\.date), [
            currentDate,
            currentDate.addingTimeInterval(-2 * 60),
            currentDate.addingTimeInterval(-1 * 60),
        ])
        XCTAssertTrue(delegate.loggedEvents.contains { event in
            event.type == .receive && event.message.contains("accepted=2")
        })
    }

    func testSensorHistoryReadLogsRejectedSampleDetails() throws {
        let manager = MicroTechCGMManager()
        let delegate = TestCGMManagerDelegate(expectedReadingResultCount: 3)
        manager.delegateQueue = .main
        manager.cgmManagerDelegate = delegate
        let session = makeSession()
        let sensor = makeSensor(session: session)
        let currentDate = Date(timeIntervalSince1970: 1_700_000_000)
        delegate.startDateForFiltering = currentDate.addingTimeInterval(-2 * 60)

        manager.registerSensorForTesting(sensor)

        manager.microTechSensorDidConnect(sensor, session: session)
        manager.microTechSensor(
            sensor,
            didRead: makeReading(
                sampleNumber: 42,
                glucoseMgdl: 123,
                receivedAt: currentDate
            )
        )
        manager.microTechSensor(
            sensor,
            didReadHistory: MicroTechAidexHistoryPacket(
                rawBytes: Data([0x23]),
                startTimeOffset: 41,
                records: [
                    MicroTechAidexHistoryRecord(timeOffset: 41, glucose: 122, rawValue: 122),
                ]
            )
        )
        manager.microTechSensor(
            sensor,
            didReadHistory: MicroTechAidexHistoryPacket(
                rawBytes: Data([0x23]),
                startTimeOffset: 39,
                records: [
                    MicroTechAidexHistoryRecord(timeOffset: 39, glucose: 121, rawValue: 121),
                    MicroTechAidexHistoryRecord(timeOffset: 40, glucose: 450, rawValue: 450),
                    MicroTechAidexHistoryRecord(timeOffset: 41, glucose: 122, rawValue: 122),
                    MicroTechAidexHistoryRecord(timeOffset: 43, glucose: 124, rawValue: 124),
                ]
            )
        )

        wait(for: [delegate.readingResultsExpectation], timeout: 1)
        guard let historyLog = delegate.loggedEvents.last(where: { event in
            event.type == .receive &&
                event.message.contains("history processed serial=ABC123 records=4 accepted=0 invalid=1 duplicate=1 tooNew=1 filtered=1")
        })?.message else {
            return XCTFail("Expected detailed history rejection log")
        }
        XCTAssertTrue(historyLog.contains("invalid=[sample=40 value=450 quality=0 raw=450]"))
        XCTAssertTrue(historyLog.contains("duplicate=[sample=41]"))
        XCTAssertTrue(historyLog.contains("tooNew=[sample=43 latest=42]"))
        XCTAssertTrue(historyLog.contains("filtered=[sample=39"))
    }

    func testHistoryReadRequestsNextPacketUntilCurrentSampleIsReached() throws {
        let manager = MicroTechCGMManager()
        let delegate = TestCGMManagerDelegate(expectedReadingResultCount: 2)
        manager.delegateQueue = .main
        manager.cgmManagerDelegate = delegate
        let session = makeSession()
        let material = MicroTechAidexKeyMaterial.derive(serial: session.sensorSerial)
        let peripheralSession = FakeMicroTechPeripheralSession(
            deviceIdentifier: session.remoteIdentifier,
            deviceName: session.deviceName,
            f002Challenge: try encryptedChallenge(for: material)
        )
        let sensor = MicroTechSensor(session: session, peripheralSession: peripheralSession, pairingKeyTimeout: 0)
        sensor.delegate = manager
        manager.registerSensorForTesting(sensor)
        try sensor.start()

        manager.microTechSensor(
            sensor,
            didRead: makeReading(
                sampleNumber: 70,
                glucoseMgdl: 123,
                receivedAt: Date(timeIntervalSince1970: 1_700_000_000)
            )
        )
        manager.microTechSensor(
            sensor,
            didReadHistory: MicroTechAidexHistoryPacket(
                rawBytes: Data([0x23]),
                startTimeOffset: 60,
                records: [
                    MicroTechAidexHistoryRecord(timeOffset: 60, glucose: 110, rawValue: 110),
                    MicroTechAidexHistoryRecord(timeOffset: 61, glucose: 111, rawValue: 111),
                    MicroTechAidexHistoryRecord(timeOffset: 62, glucose: 112, rawValue: 112),
                ]
            )
        )

        wait(for: [delegate.readingResultsExpectation], timeout: 1)
        let builder = MicroTechAidexCommandBuilder(keyMaterial: material)
        let firstHistoryCommand = try builder.cmd23(index: 60).microTechHexadecimalString
        let nextHistoryCommand = try builder.cmd23(index: 63).microTechHexadecimalString
        XCTAssertTrue(peripheralSession.calls.contains(.write(firstHistoryCommand, MicroTechAidexProfile.f002UUID.uuidString)))
        XCTAssertTrue(peripheralSession.calls.contains(.write(nextHistoryCommand, MicroTechAidexProfile.f002UUID.uuidString)))
        XCTAssertTrue(delegate.loggedEvents.contains { event in
            event.type == .send && event.message.contains("history continuation requested from=63 current=70")
        })
    }

    func testSensorHistoryReadUsesActivationTimeWhenCurrentReadingIsMissing() throws {
        let manager = MicroTechCGMManager()
        let delegate = TestCGMManagerDelegate(expectedReadingResultCount: 1)
        manager.delegateQueue = .main
        manager.cgmManagerDelegate = delegate
        let session = makeSession()
        let sensor = makeSensor(session: session)
        let activationTime = Date(timeIntervalSince1970: 1_700_000_000)

        manager.registerSensorForTesting(sensor)

        manager.microTechSensorDidConnect(sensor, session: session)
        manager.microTechSensor(sensor, didActivateAt: activationTime)
        manager.microTechSensor(
            sensor,
            didReadHistory: MicroTechAidexHistoryPacket(
                rawBytes: Data([0x23]),
                startTimeOffset: 41,
                records: [
                    MicroTechAidexHistoryRecord(
                        timeOffset: 41,
                        glucose: 122,
                        rawValue: 122
                    ),
                ]
            )
        )

        wait(for: [delegate.readingResultsExpectation], timeout: 1)
        XCTAssertEqual(delegate.newDataSampleSyncIdentifiers, ["ABC123-41"])
        XCTAssertEqual(delegate.newDataSamples.single?.date, activationTime.addingTimeInterval(41 * 60))
        XCTAssertEqual(delegate.noDataCount, 0)
        XCTAssertTrue(delegate.loggedEvents.contains { event in
            event.type == .receive && event.message.contains("history processed serial=ABC123 records=1 accepted=1")
        })
        XCTAssertTrue(delegate.loggedEvents.contains { event in
            event.type == .receive && event.message.contains("anchor=activationTime")
        })
    }

    func testDeleteClearsSensorStatePreservesUploadReadingsAndStopsActiveSensor() throws {
        var state = MicroTechCGMManagerState()
        state.remoteIdentifier = UUID(uuidString: "00000000-0000-0000-0000-000000000123")!
        state.deviceName = "LinX-ABC123"
        state.sensorSerial = "ABC123"
        state.activationTime = Date(timeIntervalSince1970: 1_699_999_000)
        state.lastReadingDate = Date(timeIntervalSince1970: 1_700_000_000)
        state.latestReading = makeReading(
            sampleNumber: 42,
            glucoseMgdl: 123,
            receivedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        state.latestSampleNumber = 42
        state.uploadReadings = true
        let manager = MicroTechCGMManager(state: state)
        let delegate = TestCGMManagerDelegate(expectedReadingResultCount: 0)
        manager.delegateQueue = .main
        manager.cgmManagerDelegate = delegate
        let session = makeSession()
        let material = MicroTechAidexKeyMaterial.derive(serial: session.sensorSerial)
        let peripheralSession = FakeMicroTechPeripheralSession(
            deviceIdentifier: session.remoteIdentifier,
            deviceName: session.deviceName,
            f002Challenge: try encryptedChallenge(for: material)
        )
        let sensor = MicroTechSensor(session: session, peripheralSession: peripheralSession, pairingKeyTimeout: 0)
        sensor.delegate = manager
        manager.registerSensorForTesting(sensor)
        try sensor.start()
        let deletionExpectation = expectation(description: "manager deletion")

        manager.delete {
            deletionExpectation.fulfill()
        }

        wait(for: [deletionExpectation], timeout: 1)
        wait(for: [delegate.readingResultsExpectation], timeout: 0.1)
        XCTAssertNil(manager.state.remoteIdentifier)
        XCTAssertNil(manager.state.deviceName)
        XCTAssertNil(manager.state.sensorSerial)
        XCTAssertNil(manager.state.activationTime)
        XCTAssertNil(manager.state.lastReadingDate)
        XCTAssertNil(manager.state.latestReading)
        XCTAssertNil(manager.state.latestSampleNumber)
        XCTAssertEqual(manager.state.uploadReadings, true)
        XCTAssertEqual(1, peripheralSession.calls.filter { $0 == .disconnect }.count)
    }

    func testReadFromDeletedSensorIsIgnored() throws {
        let manager = MicroTechCGMManager()
        let delegate = TestCGMManagerDelegate(expectedReadingResultCount: 0)
        manager.delegateQueue = .main
        manager.cgmManagerDelegate = delegate
        let session = makeSession(sensorSerial: "ABC123")
        let sensor = makeSensor(session: session)
        let deletionExpectation = expectation(description: "manager deletion")

        manager.registerSensorForTesting(sensor)

        manager.microTechSensorDidConnect(sensor, session: session)
        manager.delete {
            deletionExpectation.fulfill()
        }
        manager.microTechSensor(
            sensor,
            didRead: makeReading(
                sampleNumber: 42,
                glucoseMgdl: 123,
                receivedAt: Date(timeIntervalSince1970: 1_700_000_000),
                sensorSerial: "ABC123"
            )
        )

        wait(for: [deletionExpectation], timeout: 1)
        wait(for: [delegate.readingResultsExpectation], timeout: 0.1)
        XCTAssertNil(manager.state.sensorSerial)
        XCTAssertNil(manager.state.latestSampleNumber)
        XCTAssertTrue(delegate.readingResults.isEmpty)
    }

    func testConnectFromDeletedSensorIsIgnored() throws {
        let manager = MicroTechCGMManager()
        let delegate = TestCGMManagerDelegate(expectedReadingResultCount: 0)
        manager.delegateQueue = .main
        manager.cgmManagerDelegate = delegate
        let session = makeSession(sensorSerial: "ABC123")
        let sensor = makeSensor(session: session)
        let deletionExpectation = expectation(description: "manager deletion")

        manager.registerSensorForTesting(sensor)

        manager.microTechSensorDidConnect(sensor, session: session)
        manager.delete {
            deletionExpectation.fulfill()
        }
        manager.microTechSensorDidConnect(sensor, session: session)

        wait(for: [deletionExpectation], timeout: 1)
        wait(for: [delegate.readingResultsExpectation], timeout: 0.1)
        XCTAssertNil(manager.state.remoteIdentifier)
        XCTAssertNil(manager.state.deviceName)
        XCTAssertNil(manager.state.sensorSerial)
        XCTAssertNil(manager.state.latestSampleNumber)
        XCTAssertTrue(delegate.readingResults.isEmpty)
    }

    func testConnectAfterDeleteBeforeFirstActiveSensorIsIgnored() throws {
        let manager = MicroTechCGMManager()
        let session = makeSession(sensorSerial: "ABC123")
        let sensor = makeSensor(session: session)
        let deletionExpectation = expectation(description: "manager deletion")

        manager.delete {
            deletionExpectation.fulfill()
        }
        wait(for: [deletionExpectation], timeout: 1)

        manager.microTechSensorDidConnect(sensor, session: session)

        XCTAssertNil(manager.state.remoteIdentifier)
        XCTAssertNil(manager.state.deviceName)
        XCTAssertNil(manager.state.sensorSerial)
        XCTAssertNil(manager.state.latestSampleNumber)
    }

    func testReadFromPreviousSensorIsIgnoredAfterNewSensorConnects() throws {
        let manager = MicroTechCGMManager()
        let delegate = TestCGMManagerDelegate(expectedReadingResultCount: 1)
        manager.delegateQueue = .main
        manager.cgmManagerDelegate = delegate
        let sessionA = makeSession(
            remoteIdentifier: UUID(uuidString: "00000000-0000-0000-0000-000000000123")!,
            deviceName: "LinX-ABC123",
            sensorSerial: "ABC123"
        )
        let sessionB = makeSession(
            remoteIdentifier: UUID(uuidString: "00000000-0000-0000-0000-000000000456")!,
            deviceName: "LinX-XYZ789",
            sensorSerial: "XYZ789"
        )
        let sensorA = makeSensor(session: sessionA)
        let sensorB = makeSensor(session: sessionB)

        manager.registerSensorForTesting(sensorA)
        manager.microTechSensorDidConnect(sensorA, session: sessionA)
        manager.registerSensorForTesting(sensorB)
        manager.microTechSensorDidConnect(sensorB, session: sessionB)
        manager.microTechSensor(
            sensorA,
            didRead: makeReading(
                sampleNumber: 42,
                glucoseMgdl: 123,
                receivedAt: Date(timeIntervalSince1970: 1_700_000_000),
                sensorSerial: "ABC123"
            )
        )
        manager.microTechSensor(
            sensorB,
            didRead: makeReading(
                sampleNumber: 43,
                glucoseMgdl: 124,
                receivedAt: Date(timeIntervalSince1970: 1_700_000_300),
                sensorSerial: "XYZ789"
            )
        )

        wait(for: [delegate.readingResultsExpectation], timeout: 1)
        XCTAssertEqual(manager.state.sensorSerial, "XYZ789")
        XCTAssertEqual(manager.state.deviceName, "LinX-XYZ789")
        XCTAssertEqual(manager.state.latestSampleNumber, 43)
        XCTAssertEqual(delegate.newDataSampleSyncIdentifiers, ["XYZ789-43"])
    }

    func testNewSensorConnectionClearsPreviousReadingTrackingBeforeAcceptingNewSamples() throws {
        let manager = MicroTechCGMManager()
        let delegate = TestCGMManagerDelegate(expectedReadingResultCount: 2)
        manager.delegateQueue = .main
        manager.cgmManagerDelegate = delegate
        let sessionA = makeSession(
            remoteIdentifier: UUID(uuidString: "00000000-0000-0000-0000-000000000123")!,
            deviceName: "LinX-ABC123",
            sensorSerial: "ABC123"
        )
        let sessionB = makeSession(
            remoteIdentifier: UUID(uuidString: "00000000-0000-0000-0000-000000000456")!,
            deviceName: "LinX-XYZ789",
            sensorSerial: "XYZ789"
        )
        let sensorA = makeSensor(session: sessionA)
        let sensorB = makeSensor(session: sessionB)
        let readingA = makeReading(
            sampleNumber: 100,
            glucoseMgdl: 123,
            receivedAt: Date(timeIntervalSince1970: 1_700_000_000),
            sensorSerial: "ABC123"
        )
        let readingB = makeReading(
            sampleNumber: 1,
            glucoseMgdl: 124,
            receivedAt: Date(timeIntervalSince1970: 1_700_000_300),
            sensorSerial: "XYZ789"
        )

        manager.registerSensorForTesting(sensorA)
        manager.microTechSensorDidConnect(sensorA, session: sessionA)
        manager.microTechSensor(sensorA, didRead: readingA)
        manager.registerSensorForTesting(sensorB)
        manager.microTechSensorDidConnect(sensorB, session: sessionB)
        manager.microTechSensor(sensorB, didRead: readingB)

        wait(for: [delegate.readingResultsExpectation], timeout: 1)
        XCTAssertEqual(delegate.newDataSampleSyncIdentifiers, ["ABC123-100", "XYZ789-1"])
        XCTAssertEqual(manager.state.sensorSerial, "XYZ789")
        XCTAssertEqual(manager.state.deviceName, "LinX-XYZ789")
        XCTAssertEqual(manager.state.latestSampleNumber, 1)
        XCTAssertEqual(manager.state.latestReading, readingB)
    }

    func testConnectFromPreviousSensorIsIgnoredAfterNewSensorConnects() throws {
        let manager = MicroTechCGMManager()
        let sessionA = makeSession(
            remoteIdentifier: UUID(uuidString: "00000000-0000-0000-0000-000000000123")!,
            deviceName: "LinX-ABC123",
            sensorSerial: "ABC123"
        )
        let sessionB = makeSession(
            remoteIdentifier: UUID(uuidString: "00000000-0000-0000-0000-000000000456")!,
            deviceName: "LinX-XYZ789",
            sensorSerial: "XYZ789"
        )
        let sensorA = makeSensor(session: sessionA)
        let sensorB = makeSensor(session: sessionB)

        manager.registerSensorForTesting(sensorA)
        manager.microTechSensorDidConnect(sensorA, session: sessionA)
        manager.registerSensorForTesting(sensorB)
        manager.microTechSensorDidConnect(sensorB, session: sessionB)
        manager.microTechSensorDidConnect(sensorA, session: sessionA)

        XCTAssertEqual(manager.state.remoteIdentifier, sessionB.remoteIdentifier)
        XCTAssertEqual(manager.state.sensorSerial, "XYZ789")
        XCTAssertEqual(manager.state.deviceName, "LinX-XYZ789")
    }

    func testConnectionTimeoutControllerFiresAndCanCancel() {
        let queue = DispatchQueue(label: "MicroTechCGMManagerTests.connectionTimeout")
        let controller = MicroTechConnectionTimeoutController(timeout: 0.01, queue: queue)
        let fired = expectation(description: "connection timeout fired")
        let cancelled = expectation(description: "cancelled timeout did not fire")
        cancelled.isInverted = true
        let firedIdentifier = UUID(uuidString: "00000000-0000-0000-0000-000000000111")!
        let cancelledIdentifier = UUID(uuidString: "00000000-0000-0000-0000-000000000222")!

        controller.schedule(identifier: firedIdentifier) { identifier in
            XCTAssertEqual(identifier, firedIdentifier)
            fired.fulfill()
        }
        controller.schedule(identifier: cancelledIdentifier) { _ in
            cancelled.fulfill()
        }
        controller.cancel(identifier: cancelledIdentifier)

        wait(for: [fired, cancelled], timeout: 0.2)
    }

    func testRealBluetoothManagerShutdownClearsCallbacksBeforeCompletion() {
        let identifier = UUID(uuidString: "00000000-0000-0000-0000-000000000123")!
        let connectionTimeouts = SpyMicroTechConnectionTimeoutController(scheduledIdentifiers: [identifier])
        let configurationTimeouts = SpyMicroTechConnectionTimeoutController(scheduledIdentifiers: [identifier])
        let bluetoothManager = MicroTechBluetoothManager(
            initialConnectionMode: .direct,
            centralManagerOptions: nil,
            connectionTimeouts: connectionTimeouts,
            configurationTimeouts: configurationTimeouts
        )
        let delegate = ShutdownBluetoothManagerDelegate()
        let peripheralDelegate = ShutdownPeripheralManagerDelegate()
        let peripheralManager = FakeManagedMicroTechPeripheralManager(
            deviceIdentifier: identifier,
            deviceName: "LinX-ABC123",
            isConnected: true
        )
        let restoredPeripheral = FakeRestoredMicroTechPeripheralReference(
            identifier: identifier,
            name: "LinX-ABC123"
        )
        let shutdownCompleted = expectation(description: "Bluetooth manager shutdown completed")
        let rebindBeforeCompletionRejected = expectation(
            description: "log handler rebind before shutdown completion rejected"
        )
        let centralStateObserved = expectation(description: "initial central state observed")
        bluetoothManager.whenCentralStateObservedForTesting {
            centralStateObserved.fulfill()
        }
        wait(for: [centralStateObserved], timeout: 1)
        peripheralManager.delegate = peripheralDelegate
        bluetoothManager.delegate = delegate
        bluetoothManager.logHandler = { _, _ in }
        bluetoothManager.injectStateForTesting(
            activePeripheralManager: peripheralManager,
            managedPeripherals: [peripheralManager],
            restoredPeripherals: [restoredPeripheral],
            configuringPeripheralIDs: [identifier],
            hasScanTimeout: true
        )

        let stateBeforeShutdown = bluetoothManager.stateSnapshotForTesting()
        XCTAssertEqual(stateBeforeShutdown.activeRemoteIdentifier, identifier)
        XCTAssertEqual(stateBeforeShutdown.managedPeripheralCount, 1)
        XCTAssertEqual(stateBeforeShutdown.restoredPeripheralCount, 1)
        XCTAssertEqual(stateBeforeShutdown.configuringPeripheralCount, 1)
        XCTAssertTrue(stateBeforeShutdown.hasScanTimeout)
        XCTAssertTrue(bluetoothManager.isConnected)
        bluetoothManager.willCompleteShutdownForTesting = {
            bluetoothManager.logHandler = { _, _ in
                XCTFail("shutdown manager must reject a replacement log handler before completion")
            }
            XCTAssertNil(bluetoothManager.logHandler)
            rebindBeforeCompletionRejected.fulfill()
        }

        bluetoothManager.shutdown {
            let stateAfterShutdown = bluetoothManager.stateSnapshotForTesting()
            XCTAssertNil(bluetoothManager.delegate)
            XCTAssertNil(bluetoothManager.logHandler)
            XCTAssertTrue(stateAfterShutdown.isShutdown)
            XCTAssertNil(stateAfterShutdown.activeRemoteIdentifier)
            XCTAssertEqual(stateAfterShutdown.managedPeripheralCount, 0)
            XCTAssertEqual(stateAfterShutdown.restoredPeripheralCount, 0)
            XCTAssertEqual(stateAfterShutdown.configuringPeripheralCount, 0)
            XCTAssertFalse(stateAfterShutdown.hasScanTimeout)
            XCTAssertFalse(bluetoothManager.isScanning)
            XCTAssertFalse(bluetoothManager.isConnected)
            shutdownCompleted.fulfill()
        }

        wait(for: [rebindBeforeCompletionRejected, shutdownCompleted], timeout: 1)
        XCTAssertEqual(connectionTimeouts.cancelAllCallCount, 1)
        XCTAssertEqual(configurationTimeouts.cancelAllCallCount, 1)
        XCTAssertTrue(connectionTimeouts.scheduledIdentifiers.isEmpty)
        XCTAssertTrue(configurationTimeouts.scheduledIdentifiers.isEmpty)
        XCTAssertEqual(peripheralManager.disconnectCallCount, 1)
        XCTAssertNil(peripheralManager.delegate)

        bluetoothManager.logHandler = { _, _ in
            XCTFail("shutdown manager must reject a replacement log handler")
        }
        XCTAssertNil(bluetoothManager.logHandler)
    }

    func testConnectionTimeoutControllerCancelAllInvalidatesScheduledHandlers() {
        let queue = DispatchQueue(label: "MicroTechCGMManagerTests.connectionTimeout.cancelAll")
        queue.suspend()
        let timeout: TimeInterval = 0.01
        let controller = MicroTechConnectionTimeoutController(timeout: timeout, queue: queue)
        let lock = NSLock()
        var firedIdentifiers: [UUID] = []
        let queueDrained = expectation(description: "controlled timeout queue drained")

        controller.schedule(identifier: UUID()) { identifier in
            lock.lock()
            firedIdentifiers.append(identifier)
            lock.unlock()
        }
        controller.schedule(identifier: UUID()) { identifier in
            lock.lock()
            firedIdentifiers.append(identifier)
            lock.unlock()
        }

        controller.cancelAll()
        queue.asyncAfter(deadline: .now() + timeout * 10) {
            queueDrained.fulfill()
        }
        queue.resume()

        wait(for: [queueDrained], timeout: 1)
        lock.lock()
        let recordedIdentifiers = firedIdentifiers
        lock.unlock()
        XCTAssertTrue(recordedIdentifiers.isEmpty)
    }

    func testShutdownReleasesManagerQueueWhileLogHandlerIsBlockedAndWaitsAllCompletions() {
        let cleanupStarted = expectation(description: "Bluetooth resource cleanup started")
        let connectionTimeouts = SpyMicroTechConnectionTimeoutController(onCancelAll: {
            cleanupStarted.fulfill()
        })
        let bluetoothManager = MicroTechBluetoothManager(
            initialConnectionMode: .direct,
            centralManagerOptions: nil,
            connectionTimeouts: connectionTimeouts,
            configurationTimeouts: SpyMicroTechConnectionTimeoutController()
        )
        let centralStateObserved = expectation(description: "initial central state observed")
        bluetoothManager.whenCentralStateObservedForTesting {
            centralStateObserved.fulfill()
        }
        wait(for: [centralStateObserved], timeout: 1)

        bluetoothManager.logHandler = { _, _ in }
        bluetoothManager.flushLogsForTesting()

        let logHandlerEntered = expectation(description: "blocking log handler entered")
        let releaseLogHandler = DispatchSemaphore(value: 0)
        let logHandlerLock = NSLock()
        var isFirstLogHandlerCall = true
        bluetoothManager.logHandler = { _, _ in
            logHandlerLock.lock()
            let shouldBlock = isFirstLogHandlerCall
            isFirstLogHandlerCall = false
            logHandlerLock.unlock()
            if shouldBlock {
                logHandlerEntered.fulfill()
                releaseLogHandler.wait()
            }
        }
        bluetoothManager.handleDidConnect(identifier: UUID())
        wait(for: [logHandlerEntered], timeout: 1)

        let completionLock = NSLock()
        var completionCount = 0
        var completionRanBeforeRelease = false
        var mayComplete = false
        let allShutdownsCompleted = expectation(description: "all shutdown requests completed")
        allShutdownsCompleted.expectedFulfillmentCount = 2
        let recordCompletion = {
            completionLock.lock()
            completionCount += 1
            completionRanBeforeRelease = completionRanBeforeRelease || !mayComplete
            completionLock.unlock()
            allShutdownsCompleted.fulfill()
        }

        bluetoothManager.shutdown(completion: recordCompletion)
        bluetoothManager.shutdown(completion: recordCompletion)
        wait(for: [cleanupStarted], timeout: 1)

        let stateReadCompleted = expectation(description: "manager queue remains available")
        let stateLock = NSLock()
        var statesWhileLogHandlerBlocked: (isScanning: Bool, isConnected: Bool)?
        DispatchQueue.global(qos: .userInitiated).async {
            let states = (bluetoothManager.isScanning, bluetoothManager.isConnected)
            stateLock.lock()
            statesWhileLogHandlerBlocked = states
            stateLock.unlock()
            stateReadCompleted.fulfill()
        }

        wait(for: [stateReadCompleted], timeout: 0.5)
        completionLock.lock()
        XCTAssertEqual(completionCount, 0)
        mayComplete = true
        completionLock.unlock()

        releaseLogHandler.signal()
        wait(for: [allShutdownsCompleted], timeout: 1)

        stateLock.lock()
        let recordedStates = statesWhileLogHandlerBlocked
        stateLock.unlock()
        completionLock.lock()
        let recordedCompletionCount = completionCount
        let recordedEarlyCompletion = completionRanBeforeRelease
        completionLock.unlock()
        XCTAssertEqual(recordedStates?.isScanning, false)
        XCTAssertEqual(recordedStates?.isConnected, false)
        XCTAssertEqual(recordedCompletionCount, 2)
        XCTAssertFalse(recordedEarlyCompletion)
        XCTAssertNil(bluetoothManager.logHandler)
    }

    func testShutdownManagerIgnoresLateCallbacksAndCannotRestartScanning() {
        let connectionTimeouts = SpyMicroTechConnectionTimeoutController()
        let configurationTimeouts = SpyMicroTechConnectionTimeoutController()
        let bluetoothManager = MicroTechBluetoothManager(
            initialConnectionMode: .direct,
            centralManagerOptions: nil,
            connectionTimeouts: connectionTimeouts,
            configurationTimeouts: configurationTimeouts
        )
        let initialShutdownCompleted = expectation(description: "initial shutdown completed")
        bluetoothManager.shutdown {
            initialShutdownCompleted.fulfill()
        }
        wait(for: [initialShutdownCompleted], timeout: 1)

        let repeatedShutdownCompleted = expectation(description: "repeated shutdown completed")
        bluetoothManager.shutdown {
            repeatedShutdownCompleted.fulfill()
        }
        wait(for: [repeatedShutdownCompleted], timeout: 1)

        bluetoothManager.logHandler = { _, _ in }
        bluetoothManager.flushLogsForTesting()

        let identifier = UUID(uuidString: "00000000-0000-0000-0000-000000000456")!
        let peripheralManager = FakeManagedMicroTechPeripheralManager(
            deviceIdentifier: identifier,
            deviceName: "LinX-XYZ789",
            isConnected: true
        )
        let restoredPeripheral = FakeRestoredMicroTechPeripheralReference(
            identifier: identifier,
            name: "LinX-XYZ789"
        )
        let delegate = ShutdownBluetoothManagerDelegate()
        let peripheralDelegate = ShutdownPeripheralManagerDelegate()
        let callbackLogs = ThreadSafeMessages()
        peripheralManager.delegate = peripheralDelegate
        bluetoothManager.delegate = delegate
        bluetoothManager.logHandler = { message, _ in
            callbackLogs.append(message)
        }
        bluetoothManager.injectStateForTesting(
            activePeripheralManager: peripheralManager,
            managedPeripherals: [peripheralManager],
            restoredPeripherals: [restoredPeripheral],
            configuringPeripheralIDs: [identifier],
            hasScanTimeout: true
        )
        let stateBeforeLateWork = bluetoothManager.stateSnapshotForTesting()

        let lateCentralManager = CBCentralManager(delegate: nil, queue: nil)
        bluetoothManager.centralManagerDidUpdateState(lateCentralManager)
        bluetoothManager.centralManager(lateCentralManager, willRestoreState: [:])
        bluetoothManager.configureConnectionMode(.broadcast)
        bluetoothManager.scan(remoteIdentifier: UUID())
        bluetoothManager.scanForBroadcast(remoteIdentifier: UUID())
        bluetoothManager.refreshConnectedPeripheral()
        bluetoothManager.stopScanning()
        bluetoothManager.disconnect()
        bluetoothManager.forgetPeripheral()

        var discoveryConnectCallCount = 0
        bluetoothManager.handleDiscoveredPeripheral(
            identifier: identifier,
            peripheralName: "LinX-XYZ789",
            advertisementData: [:],
            rssi: -60
        ) {
            discoveryConnectCallCount += 1
        }
        bluetoothManager.handleDidConnect(identifier: identifier)
        bluetoothManager.handleDidFailToConnect(identifier: identifier, error: ShutdownTestError.forcedFailure)
        bluetoothManager.handleDidDisconnect(identifier: identifier, error: ShutdownTestError.forcedFailure)
        var connectionEventConnectCallCount = 0
        bluetoothManager.handleConnectionEvent(
            .peerConnected,
            identifier: identifier,
            peripheralName: "LinX-XYZ789"
        ) {
            connectionEventConnectCallCount += 1
        }
        bluetoothManager.handleConnectionEvent(
            .peerDisconnected,
            identifier: identifier,
            peripheralName: "LinX-XYZ789",
            connectIfNeeded: {}
        )
        bluetoothManager.handlePeripheralValue(
            Data([0x01]),
            characteristic: MicroTechAidexProfile.f001UUID,
            session: peripheralManager
        )
        bluetoothManager.handlePeripheralDisconnect(peripheralManager, error: ShutdownTestError.forcedFailure)

        let stateAfterLateWork = bluetoothManager.stateSnapshotForTesting()
        bluetoothManager.flushLogsForTesting()

        XCTAssertEqual(stateAfterLateWork, stateBeforeLateWork)
        XCTAssertTrue(stateAfterLateWork.isShutdown)
        XCTAssertEqual(stateAfterLateWork.activeRemoteIdentifier, identifier)
        XCTAssertEqual(stateAfterLateWork.managedPeripheralCount, 1)
        XCTAssertEqual(stateAfterLateWork.restoredPeripheralCount, 1)
        XCTAssertEqual(stateAfterLateWork.configuringPeripheralCount, 1)
        XCTAssertTrue(stateAfterLateWork.hasScanTimeout)
        XCTAssertEqual(discoveryConnectCallCount, 0)
        XCTAssertEqual(connectionEventConnectCallCount, 0)
        XCTAssertEqual(peripheralManager.configureCallCount, 0)
        XCTAssertEqual(peripheralManager.disconnectCallCount, 0)
        XCTAssertEqual(peripheralManager.didDisconnectCallCount, 0)
        XCTAssertEqual(delegate.callbackCount, 0)
        XCTAssertEqual(peripheralDelegate.callbackCount, 0)
        XCTAssertTrue(callbackLogs.values.isEmpty)
        XCTAssertEqual(connectionTimeouts.cancelCallCount, 0)
        XCTAssertEqual(configurationTimeouts.cancelCallCount, 0)
        XCTAssertFalse(bluetoothManager.isScanning)
        XCTAssertFalse(bluetoothManager.isConnected)
    }

    func testPeripheralConnectionTimeoutIsOnlyScheduledForConnectableStates() {
        XCTAssertFalse(MicroTechBluetoothManager.shouldScheduleConnectionTimeout(for: .connected))
        XCTAssertTrue(MicroTechBluetoothManager.shouldScheduleConnectionTimeout(for: .disconnected))
        XCTAssertTrue(MicroTechBluetoothManager.shouldScheduleConnectionTimeout(for: .connecting))
        XCTAssertFalse(MicroTechBluetoothManager.shouldScheduleConnectionTimeout(for: .disconnecting))
    }

    func testDisconnectingPeripheralIsNotClaimedAsActiveConnectionAttempt() {
        let identifier = UUID(uuidString: "00000000-0000-0000-0000-000000000123")!

        XCTAssertTrue(MicroTechBluetoothManager.shouldClaimPeripheralForConnection(state: .connected))
        XCTAssertTrue(MicroTechBluetoothManager.shouldClaimPeripheralForConnection(state: .disconnected))
        XCTAssertTrue(MicroTechBluetoothManager.shouldClaimPeripheralForConnection(state: .connecting))
        XCTAssertFalse(MicroTechBluetoothManager.shouldClaimPeripheralForConnection(state: .disconnecting))
        XCTAssertEqual(
            MicroTechBluetoothManager.disconnectingPeripheralLogMessage(identifier: identifier, name: "AiDEX X-ABC123"),
            "peripheral is disconnecting \(identifier), name AiDEX X-ABC123, waiting for disconnect before reconnecting"
        )
    }

    func testConfigurationTimeoutLeavesRoomForPeripheralConfigurationOperations() {
        XCTAssertGreaterThanOrEqual(
            MicroTechBluetoothManager.defaultConfigurationTimeout,
            MicroTechPeripheralManager.defaultOperationTimeout * 2
        )
    }

    func testBluetoothRestoreIdentifierIsStableForBackgroundRecovery() {
        XCTAssertEqual(MicroTechBluetoothManager.restoreIdentifier, "com.loopkit.MicroTechCGM")
    }

    func testConfigurationProgressLogMessagesNamePeripheral() {
        let identifier = UUID(uuidString: "00000000-0000-0000-0000-000000000123")!

        XCTAssertEqual(
            MicroTechBluetoothManager.configurationAlreadyInProgressLogMessage(
                identifier: identifier,
                name: "LinX-ABC123"
            ),
            "peripheral configure already in progress \(identifier), name LinX-ABC123"
        )
        XCTAssertEqual(
            MicroTechBluetoothManager.configurationTimedOutLogMessage(
                identifier: identifier,
                name: "LinX-ABC123"
            ),
            "peripheral configure timed out \(identifier), name LinX-ABC123"
        )
    }

    func testSavedPeripheralLogMessageIdentifiesCoreBluetoothRestoreSource() {
        let identifier = UUID(uuidString: "00000000-0000-0000-0000-000000000123")!

        XCTAssertEqual(
            MicroTechBluetoothManager.savedPeripheralLogMessage(
                identifier: identifier,
                name: "LinX-ABC123",
                source: .coreBluetoothRestore
            ),
            "retrieved saved peripheral \(identifier) from CoreBluetooth restore, name Optional(\"LinX-ABC123\")"
        )
        XCTAssertEqual(
            MicroTechBluetoothManager.savedPeripheralLogMessage(
                identifier: identifier,
                name: nil,
                source: .retrievePeripherals
            ),
            "retrieved saved peripheral \(identifier) from retrievePeripherals, name nil"
        )
    }

    func testSavedSensorAcceptsRestoredPeripheralIdentifierWithoutDeviceName() {
        let remoteIdentifier = UUID(uuidString: "00000000-0000-0000-0000-000000000123")!
        var state = MicroTechCGMManagerState()
        state.remoteIdentifier = remoteIdentifier
        state.deviceName = "LinX-ABC123"
        state.sensorSerial = "ABC123"
        let manager = MicroTechCGMManager(state: state)

        XCTAssertTrue(manager.shouldConnectToMicroTechDevice(deviceName: "", identifier: remoteIdentifier))
        XCTAssertTrue(manager.shouldConnectToMicroTechDevice(deviceName: "LinX-ABC123", identifier: UUID()))
        XCTAssertFalse(manager.shouldConnectToMicroTechDevice(deviceName: "", identifier: UUID()))
    }

    func testSavedDirectSensorReconnectStartsOnlyOneSixtySecondRecoveryCycle() throws {
        let bluetoothManager = FakeMicroTechBluetoothManager()
        var scheduled: [(TimeInterval, () -> Void)] = []
        let manager = MicroTechCGMManager(
            state: makeReconnectState(),
            bluetoothManagerFactory: { bluetoothManager },
            reconnectRecoveryScheduler: { scheduled.append(($0, $1)) }
        )

        XCTAssertTrue(manager.scanForSensor())
        XCTAssertTrue(manager.scanForSensor())

        XCTAssertEqual(scheduled.count, 1)
        XCTAssertEqual(try XCTUnwrap(scheduled.first?.0), 60, accuracy: 0.001)
        XCTAssertEqual(manager.reconnectRecoveryPhaseForTesting, "timing")
    }

    func testDiscoveryAndRetryDoNotResetReconnectRecoveryDeadline() {
        let remoteIdentifier = UUID(uuidString: "00000000-0000-0000-0000-000000000123")!
        let bluetoothManager = FakeMicroTechBluetoothManager()
        var scheduled: [(TimeInterval, () -> Void)] = []
        var retries: [() -> Void] = []
        let manager = MicroTechCGMManager(
            state: makeReconnectState(),
            bluetoothManagerFactory: { bluetoothManager },
            bluetoothRetryScheduler: { retries.append($0) },
            reconnectRecoveryScheduler: { scheduled.append(($0, $1)) }
        )

        XCTAssertTrue(manager.scanForSensor())
        bluetoothManager.isScanning = false
        manager.recordBluetoothFailure(MicroTechBluetoothManagerError.scanTimeout(remoteIdentifier))
        retries.forEach { $0() }
        _ = manager.shouldConnectToMicroTechDevice(deviceName: "LinX-ABC123", identifier: remoteIdentifier)

        XCTAssertEqual(scheduled.count, 1)
    }

    func testDiscoveryWithoutHandshakeStillAllowsRecoveryTimeoutToRebuild() {
        let bluetoothManager = FakeMicroTechBluetoothManager()
        var scheduled: [(TimeInterval, () -> Void)] = []
        let manager = MicroTechCGMManager(
            state: makeReconnectState(),
            bluetoothManagerFactory: { bluetoothManager },
            reconnectRecoveryScheduler: { scheduled.append(($0, $1)) }
        )
        XCTAssertTrue(manager.scanForSensor())
        manager.connectDiscoveredSensor(peripheralSession: FakeMicroTechPeripheralSession(
            deviceIdentifier: UUID(),
            deviceName: "LinX-ABC123",
            f002Challenge: Data(),
            failurePoint: .read
        ))

        scheduled[0].1()

        XCTAssertEqual(bluetoothManager.shutdownCallCount, 1)
    }

    func testHandshakeCancelsReconnectRecoveryCycle() {
        let bluetoothManager = FakeMicroTechBluetoothManager()
        var scheduled: [(TimeInterval, () -> Void)] = []
        let manager = MicroTechCGMManager(
            state: makeReconnectState(),
            bluetoothManagerFactory: { bluetoothManager },
            reconnectRecoveryScheduler: { scheduled.append(($0, $1)) }
        )

        XCTAssertTrue(manager.scanForSensor())
        guard let sensor = bluetoothManager.delegate as? MicroTechSensor else {
            return XCTFail("Expected saved sensor delegate")
        }
        manager.microTechSensorDidConnect(sensor, session: makeSession())
        scheduled[0].1()

        XCTAssertEqual(manager.reconnectRecoveryPhaseForTesting, "idle")
        XCTAssertEqual(bluetoothManager.shutdownCallCount, 0)
    }

    func testRecoveryTimeoutWaitsForShutdownBeforeCreatingReplacementManager() {
        let first = FakeMicroTechBluetoothManager()
        let second = FakeMicroTechBluetoothManager()
        var factoryCalls = 0
        var scheduled: [(TimeInterval, () -> Void)] = []
        let manager = MicroTechCGMManager(
            state: makeReconnectState(),
            bluetoothManagerFactory: {
                factoryCalls += 1
                return factoryCalls == 1 ? first : second
            },
            reconnectRecoveryScheduler: { scheduled.append(($0, $1)) }
        )

        XCTAssertTrue(manager.scanForSensor())
        scheduled[0].1()

        XCTAssertEqual(first.shutdownCallCount, 1)
        XCTAssertEqual(factoryCalls, 1)
        XCTAssertEqual(manager.reconnectRecoveryPhaseForTesting, "shuttingDown")

        first.completeShutdown()
        XCTAssertEqual(factoryCalls, 2)
        XCTAssertEqual(second.activatedRemoteIdentifiers, [nil])
    }

    func testShutdownCompletionRechecksDeletionAndConnectionMode() {
        for action in ["delete", "broadcast"] {
            let first = FakeMicroTechBluetoothManager()
            let second = FakeMicroTechBluetoothManager()
            var factoryCalls = 0
            var scheduled: [(TimeInterval, () -> Void)] = []
            let manager = MicroTechCGMManager(
                state: makeReconnectState(),
                bluetoothManagerFactory: {
                    factoryCalls += 1
                    return factoryCalls == 1 ? first : second
                },
                reconnectRecoveryScheduler: { scheduled.append(($0, $1)) }
            )
            XCTAssertTrue(manager.scanForSensor())
            scheduled[0].1()

            if action == "delete" {
                manager.delete {}
            } else {
                XCTAssertTrue(manager.configureConnectionMode(.broadcast))
            }
            first.completeShutdown()

            XCTAssertEqual(factoryCalls, 1, action)
            XCTAssertTrue(second.activatedRemoteIdentifiers.isEmpty, action)
            XCTAssertEqual(manager.reconnectRecoveryPhaseForTesting, "idle", action)
        }
    }

    func testReplacementManagerScansBySerialWithoutSavedIdentifier() {
        let first = FakeMicroTechBluetoothManager()
        let second = FakeMicroTechBluetoothManager()
        var managers = [first, second]
        var scheduled: [(TimeInterval, () -> Void)] = []
        let manager = MicroTechCGMManager(
            state: makeReconnectState(),
            bluetoothManagerFactory: { managers.removeFirst() },
            reconnectRecoveryScheduler: { scheduled.append(($0, $1)) }
        )

        XCTAssertTrue(manager.scanForSensor())
        scheduled[0].1()
        first.completeShutdown()

        XCTAssertNil(manager.state.remoteIdentifier)
        XCTAssertEqual(manager.state.sensorSerial, "ABC123")
        XCTAssertEqual(second.activatedRemoteIdentifiers, [nil])
        XCTAssertTrue((second.delegate as AnyObject?) is MicroTechSensor)
    }

    func testFirstOnboardingAndBroadcastModeDoNotStartReconnectRecovery() {
        var scheduled: [(TimeInterval, () -> Void)] = []
        let firstOnboarding = MicroTechCGMManager(
            state: MicroTechCGMManagerState(),
            bluetoothManagerFactory: { FakeMicroTechBluetoothManager() },
            reconnectRecoveryScheduler: { scheduled.append(($0, $1)) }
        )
        var broadcastState = makeReconnectState()
        broadcastState.connectionMode = .broadcast
        let broadcast = MicroTechCGMManager(
            state: broadcastState,
            bluetoothManagerFactory: { FakeMicroTechBluetoothManager() },
            reconnectRecoveryScheduler: { scheduled.append(($0, $1)) }
        )

        XCTAssertTrue(firstOnboarding.scanForSensor())
        XCTAssertTrue(broadcast.scanForSensor())
        XCTAssertTrue(scheduled.isEmpty)
    }

    func testOldRecoveryTimeoutCannotReplaceNewConnection() {
        let bluetoothManager = FakeMicroTechBluetoothManager()
        var scheduled: [(TimeInterval, () -> Void)] = []
        let manager = MicroTechCGMManager(
            state: makeReconnectState(),
            bluetoothManagerFactory: { bluetoothManager },
            reconnectRecoveryScheduler: { scheduled.append(($0, $1)) }
        )

        XCTAssertTrue(manager.scanForSensor())
        guard let sensor = bluetoothManager.delegate as? MicroTechSensor else {
            return XCTFail("Expected saved sensor delegate")
        }
        manager.microTechSensorDidConnect(sensor, session: makeSession())
        manager.microTechSensorDidDisconnect(sensor)
        manager.microTechSensorDidConnect(sensor, session: makeSession())
        scheduled.forEach { $0.1() }

        XCTAssertEqual(bluetoothManager.shutdownCallCount, 0)
    }

    func testReconnectEligibilityRequiresPriorHandshakeSerialDirectModeNotDeletedAndNotCurrentlyConnected() {
        struct Case {
            let priorHandshake: Bool
            let serial: String?
            let mode: MicroTechCGMConnectionMode
            let deleted: Bool
            let currentHandshake: Bool
            let expected: Bool
        }
        let cases = [
            Case(priorHandshake: true, serial: "ABC123", mode: .direct, deleted: false, currentHandshake: false, expected: true),
            Case(priorHandshake: false, serial: "ABC123", mode: .direct, deleted: false, currentHandshake: false, expected: false),
            Case(priorHandshake: true, serial: nil, mode: .direct, deleted: false, currentHandshake: false, expected: false),
            Case(priorHandshake: true, serial: "", mode: .direct, deleted: false, currentHandshake: false, expected: false),
            Case(priorHandshake: true, serial: "ABC123", mode: .broadcast, deleted: false, currentHandshake: false, expected: false),
            Case(priorHandshake: true, serial: "ABC123", mode: .direct, deleted: true, currentHandshake: false, expected: false),
            Case(priorHandshake: true, serial: "ABC123", mode: .direct, deleted: false, currentHandshake: true, expected: false),
        ]

        for testCase in cases {
            XCTAssertEqual(
                MicroTechCGMManager.isReconnectRecoveryEligible(
                    hasConnectedSensorSession: testCase.priorHandshake,
                    sensorSerial: testCase.serial,
                    connectionMode: testCase.mode,
                    isDeleted: testCase.deleted,
                    hasCurrentHandshake: testCase.currentHandshake
                ),
                testCase.expected
            )
        }
    }

    func testOldBluetoothManagerShouldConnectReadyFailureDisconnectBroadcastAndDataCallbacksAreIgnored() {
        let first = FakeMicroTechBluetoothManager()
        let second = FakeMicroTechBluetoothManager()
        var managers = [first, second]
        var scheduled: [(TimeInterval, () -> Void)] = []
        var messages: [String] = []
        let manager = MicroTechCGMManager(
            state: makeReconnectState(),
            bluetoothManagerFactory: { managers.removeFirst() },
            reconnectRecoveryScheduler: { scheduled.append(($0, $1)) }
        )
        let delegate = TestCGMManagerDelegate(expectedReadingResultCount: 0)
        manager.delegateQueue = .main
        manager.cgmManagerDelegate = delegate
        manager.onboardingDeviceLogHandler = { _, _, message in messages.append(message) }
        XCTAssertTrue(manager.scanForSensor())
        scheduled[0].1()
        first.completeShutdown()
        let before = manager.state
        let peripheral = FakeMicroTechPeripheralSession(
            deviceIdentifier: UUID(),
            deviceName: "LinX-ABC123",
            f002Challenge: Data()
        )

        XCTAssertFalse(manager.handleBluetoothShouldConnect(from: first, deviceName: "LinX-ABC123", identifier: UUID()))
        manager.handleBluetoothReady(from: first, peripheralSession: peripheral)
        manager.handleBluetoothFailure(from: first, error: MicroTechCGMManagerTestError.poweredOff)
        manager.handleBluetoothDisconnect(from: first, session: peripheral)
        manager.handleBluetoothData(from: first, value: Data([1]), characteristic: CBUUID(string: "F003"), session: peripheral)
        manager.handleBluetoothBroadcast(from: first, advertisement: MicroTechBroadcastAdvertisement(
            identifier: UUID(), localName: nil, peripheralName: nil, advertisementData: [:], rssi: -60, discoveredAt: Date()
        ))

        XCTAssertEqual(manager.state, before)
        XCTAssertEqual(second.shutdownCallCount, 0)
        wait(for: [delegate.readingResultsExpectation], timeout: 0.1)
        XCTAssertTrue(delegate.readingResults.isEmpty)
        let ignoredCallbacks = ["shouldConnect", "ready", "failure", "disconnect", "data", "broadcast"]
        for callback in ignoredCallbacks {
            XCTAssertTrue(
                delegate.loggedEvents.contains { $0.message.contains("callback=\(callback)") && $0.message.contains("reason=retiredBluetoothManager") } ||
                    messages.contains { $0.contains("callback=\(callback)") && $0.contains("reason=retiredBluetoothManager") },
                callback
            )
        }
    }

    func testOldSensorConnectDisconnectReadingHistoryActivationIgnoredAndErrorCallbacksAreIgnored() {
        let first = FakeMicroTechBluetoothManager()
        let second = FakeMicroTechBluetoothManager()
        var managers = [first, second]
        var scheduled: [(TimeInterval, () -> Void)] = []
        var retries: [() -> Void] = []
        let manager = MicroTechCGMManager(
            state: makeReconnectState(),
            bluetoothManagerFactory: { managers.removeFirst() },
            bluetoothRetryScheduler: { retries.append($0) },
            reconnectRecoveryScheduler: { scheduled.append(($0, $1)) }
        )
        let delegate = TestCGMManagerDelegate(expectedReadingResultCount: 0)
        manager.delegateQueue = .main
        manager.cgmManagerDelegate = delegate
        XCTAssertTrue(manager.scanForSensor())
        guard let oldSensor = first.delegate as? MicroTechSensor else {
            return XCTFail("Expected saved sensor delegate")
        }
        scheduled[0].1()
        first.completeShutdown()
        let before = manager.state

        manager.microTechSensorDidConnect(oldSensor, session: makeSession())
        manager.microTechSensorDidDisconnect(oldSensor)
        manager.microTechSensor(oldSensor, didRead: makeReading(sampleNumber: 999, glucoseMgdl: 200, receivedAt: Date()))
        manager.microTechSensor(
            oldSensor,
            didReadHistory: MicroTechAidexHistoryPacket(
                rawBytes: Data([0x23]),
                startTimeOffset: 41,
                records: [MicroTechAidexHistoryRecord(timeOffset: 41, glucose: 120, rawValue: 120)]
            )
        )
        manager.microTechSensor(oldSensor, didActivateAt: Date())
        manager.microTechSensor(oldSensor, didIgnorePacketType: 0x04, length: 1, hexPrefix: "04")
        manager.microTechSensor(oldSensor, didLog: "retired sensor log", type: .error)
        manager.microTechSensor(oldSensor, didError: MicroTechCGMManagerTestError.poweredOff)

        wait(for: [delegate.readingResultsExpectation], timeout: 0.1)
        XCTAssertEqual(manager.state, before)
        XCTAssertEqual(scheduled.count, 2)
        XCTAssertTrue(retries.isEmpty)
        XCTAssertTrue(delegate.readingResults.isEmpty)
        XCTAssertFalse(delegate.loggedEvents.contains { $0.message.contains("retired sensor log") })
        XCTAssertFalse(delegate.loggedEvents.contains { $0.message.contains("history processed") })
        XCTAssertFalse(delegate.loggedEvents.contains { $0.message.contains("ignored unsupported packet") })
    }

    func testOldManagerFailureBlockedBeforeMutationCannotCrossRebuild() {
        let first = FakeMicroTechBluetoothManager()
        let second = FakeMicroTechBluetoothManager()
        var managers = [first, second]
        var scheduled: [(TimeInterval, () -> Void)] = []
        let enteredBarrier = DispatchSemaphore(value: 0)
        let releaseBarrier = DispatchSemaphore(value: 0)
        let callbackFinished = expectation(description: "old manager callback finished")
        let manager = MicroTechCGMManager(
            state: makeReconnectState(),
            bluetoothManagerFactory: { managers.removeFirst() },
            reconnectRecoveryScheduler: { scheduled.append(($0, $1)) },
            callbackProcessingBarrier: {
                enteredBarrier.signal()
                releaseBarrier.wait()
            }
        )
        let delegate = TestCGMManagerDelegate(expectedReadingResultCount: 0)
        manager.delegateQueue = .main
        manager.cgmManagerDelegate = delegate
        XCTAssertTrue(manager.scanForSensor())

        DispatchQueue.global().async {
            manager.handleBluetoothFailure(from: first, error: MicroTechCGMManagerTestError.poweredOff)
            callbackFinished.fulfill()
        }
        XCTAssertEqual(enteredBarrier.wait(timeout: .now() + 1), .success)
        scheduled[0].1()
        first.completeShutdown()
        let stateAfterRebuild = manager.state
        releaseBarrier.signal()
        wait(for: [callbackFinished], timeout: 1)

        XCTAssertEqual(manager.state, stateAfterRebuild)
        XCTAssertNil(manager.state.lastConnectionErrorDescription)
        XCTAssertEqual(scheduled.count, 2)
        XCTAssertTrue(delegate.readingResults.isEmpty)
    }

    func testOldSensorHistoryBlockedBeforeMutationCannotCrossRebuild() {
        let first = FakeMicroTechBluetoothManager()
        let second = FakeMicroTechBluetoothManager()
        var managers = [first, second]
        var scheduled: [(TimeInterval, () -> Void)] = []
        let enteredBarrier = DispatchSemaphore(value: 0)
        let releaseBarrier = DispatchSemaphore(value: 0)
        let callbackFinished = expectation(description: "old sensor history callback finished")
        let manager = MicroTechCGMManager(
            state: makeReconnectState(),
            bluetoothManagerFactory: { managers.removeFirst() },
            reconnectRecoveryScheduler: { scheduled.append(($0, $1)) },
            callbackProcessingBarrier: {
                enteredBarrier.signal()
                releaseBarrier.wait()
            }
        )
        let delegate = TestCGMManagerDelegate(expectedReadingResultCount: 0)
        manager.delegateQueue = .main
        manager.cgmManagerDelegate = delegate
        XCTAssertTrue(manager.scanForSensor())
        guard let oldSensor = first.delegate as? MicroTechSensor else {
            return XCTFail("Expected saved sensor delegate")
        }

        DispatchQueue.global().async {
            manager.microTechSensor(
                oldSensor,
                didReadHistory: MicroTechAidexHistoryPacket(
                    rawBytes: Data([0x23]),
                    startTimeOffset: 41,
                    records: [MicroTechAidexHistoryRecord(timeOffset: 41, glucose: 120, rawValue: 120)]
                )
            )
            callbackFinished.fulfill()
        }
        XCTAssertEqual(enteredBarrier.wait(timeout: .now() + 1), .success)
        scheduled[0].1()
        first.completeShutdown()
        let stateAfterRebuild = manager.state
        releaseBarrier.signal()
        wait(for: [callbackFinished], timeout: 1)

        XCTAssertEqual(manager.state, stateAfterRebuild)
        XCTAssertTrue(delegate.readingResults.isEmpty)
        XCTAssertTrue(manager.emittedHistorySamplesForTesting.isEmpty)
    }

    func testShuttingDownIgnoresScanFetchInternalAndQueuedRetryWithoutCallingFactory() {
        let first = FakeMicroTechBluetoothManager()
        let second = FakeMicroTechBluetoothManager()
        var factoryCalls = 0
        var scheduled: [(TimeInterval, () -> Void)] = []
        var retries: [() -> Void] = []
        let manager = MicroTechCGMManager(
            state: makeReconnectState(),
            bluetoothManagerFactory: {
                factoryCalls += 1
                return factoryCalls == 1 ? first : second
            },
            bluetoothRetryScheduler: { retries.append($0) },
            reconnectRecoveryScheduler: { scheduled.append(($0, $1)) }
        )
        XCTAssertTrue(manager.scanForSensor())
        first.isScanning = false
        manager.recordBluetoothFailure(MicroTechBluetoothManagerError.scanTimeout(manager.state.remoteIdentifier))
        scheduled[0].1()

        XCTAssertFalse(manager.scanForSensor())
        manager.fetchNewDataIfNeeded { _ in }
        retries.forEach { $0() }
        XCTAssertEqual(factoryCalls, 1)
        XCTAssertTrue(second.activatedRemoteIdentifiers.isEmpty)
    }

    func testShutdownCompletionTransitionsDirectlyToNextTimingCycle() {
        let first = FakeMicroTechBluetoothManager()
        let second = FakeMicroTechBluetoothManager()
        var managers = [first, second]
        var scheduled: [(TimeInterval, () -> Void)] = []
        var phasesDuringScheduling: [String] = []
        var manager: MicroTechCGMManager!
        manager = MicroTechCGMManager(
            state: makeReconnectState(),
            bluetoothManagerFactory: { managers.removeFirst() },
            reconnectRecoveryScheduler: { delay, block in
                phasesDuringScheduling.append(manager.reconnectRecoveryPhaseForTesting)
                scheduled.append((delay, block))
            }
        )

        XCTAssertTrue(manager.scanForSensor())
        scheduled[0].1()
        first.completeShutdown()

        XCTAssertEqual(phasesDuringScheduling, ["timing", "timing"])
        XCTAssertEqual(manager.reconnectRecoveryPhaseForTesting, "timing")
    }

    func testRecoveryRebuildPreservesDeviceActivationLatestReadingAndHistoryDedupButClearsPendingHistory() throws {
        let first = FakeMicroTechBluetoothManager()
        let second = FakeMicroTechBluetoothManager()
        var managers = [first, second]
        var scheduled: [(TimeInterval, () -> Void)] = []
        let state = makeReconnectState()
        let manager = MicroTechCGMManager(
            state: state,
            bluetoothManagerFactory: { managers.removeFirst() },
            bluetoothRetryScheduler: { $0() },
            reconnectRecoveryScheduler: { scheduled.append(($0, $1)) }
        )
        let delegate = TestCGMManagerDelegate(expectedReadingResultCount: 4)
        manager.delegateQueue = .main
        manager.cgmManagerDelegate = delegate
        XCTAssertTrue(manager.scanForSensor())
        let firstSession = makeSession()
        let material = MicroTechAidexKeyMaterial.derive(serial: firstSession.sensorSerial)
        let firstPeripheral = FakeMicroTechPeripheralSession(
            deviceIdentifier: firstSession.remoteIdentifier,
            deviceName: firstSession.deviceName,
            f002Challenge: try encryptedChallenge(for: material)
        )
        let firstSensor = MicroTechSensor(
            session: firstSession,
            peripheralSession: firstPeripheral,
            pairingKeyTimeout: 0
        )
        firstSensor.delegate = manager
        manager.registerSensorForTesting(firstSensor)
        try firstSensor.start()
        manager.microTechSensor(
            firstSensor,
            didRead: makeReading(
                sampleNumber: 70,
                glucoseMgdl: 124,
                receivedAt: Date(timeIntervalSince1970: 1_700_000_060)
            )
        )
        manager.microTechSensor(
            firstSensor,
            didReadHistory: MicroTechAidexHistoryPacket(
                rawBytes: Data([0x23]),
                startTimeOffset: 60,
                records: [MicroTechAidexHistoryRecord(timeOffset: 60, glucose: 120, rawValue: 120)]
            )
        )
        XCTAssertEqual(manager.emittedHistorySamplesForTesting, Set([60]))
        XCTAssertEqual(manager.pendingHistoryRequestForTesting, 61)
        let builder = MicroTechAidexCommandBuilder(keyMaterial: material)
        let firstContinuationWrite = FakeMicroTechPeripheralSession.Call.write(
            try builder.cmd23(index: 61).microTechHexadecimalString,
            MicroTechAidexProfile.f002UUID.uuidString
        )
        var deadline = Date(timeIntervalSinceNow: 1)
        while Date() < deadline, !firstPeripheral.calls.contains(firstContinuationWrite) {
            Thread.sleep(forTimeInterval: 0.01)
        }
        XCTAssertTrue(firstPeripheral.calls.contains(firstContinuationWrite))
        let preservedLastReadingDate = manager.state.lastReadingDate
        first.isScanning = false
        first.isConnected = false
        manager.microTechSensorDidDisconnect(firstSensor)

        XCTAssertEqual(scheduled.count, 2)
        scheduled[1].1()
        XCTAssertNil(manager.pendingHistoryRequestForTesting)
        first.completeShutdown()

        XCTAssertEqual(manager.state.deviceName, state.deviceName)
        XCTAssertEqual(manager.state.sensorSerial, state.sensorSerial)
        XCTAssertEqual(manager.state.activationTime, state.activationTime)
        XCTAssertEqual(manager.state.latestSampleNumber, 70)
        XCTAssertEqual(manager.state.lastReadingDate, preservedLastReadingDate)
        XCTAssertEqual(manager.emittedHistorySamplesForTesting, Set([60]))
        XCTAssertNil(manager.pendingHistoryRequestForTesting)

        let secondSession = makeSession(remoteIdentifier: UUID())
        let secondPeripheral = FakeMicroTechPeripheralSession(
            deviceIdentifier: secondSession.remoteIdentifier,
            deviceName: secondSession.deviceName,
            f002Challenge: try encryptedChallenge(for: material)
        )
        let secondSensor = MicroTechSensor(
            session: secondSession,
            peripheralSession: secondPeripheral,
            pairingKeyTimeout: 0
        )
        secondSensor.delegate = manager
        manager.registerSensorForTesting(secondSensor)
        try secondSensor.start()
        manager.microTechSensor(
            secondSensor,
            didRead: makeReading(
                sampleNumber: 71,
                glucoseMgdl: 125,
                receivedAt: Date(timeIntervalSince1970: 1_700_000_120)
            )
        )
        let rebuiltHistoryWrite = FakeMicroTechPeripheralSession.Call.write(
            try builder.cmd23(index: 61).microTechHexadecimalString,
            MicroTechAidexProfile.f002UUID.uuidString
        )
        deadline = Date(timeIntervalSinceNow: 1)
        while Date() < deadline, !secondPeripheral.calls.contains(rebuiltHistoryWrite) {
            Thread.sleep(forTimeInterval: 0.01)
        }
        XCTAssertTrue(secondPeripheral.calls.contains(rebuiltHistoryWrite))
        XCTAssertEqual(manager.pendingHistoryRequestForTesting, 61)
        manager.microTechSensor(
            secondSensor,
            didReadHistory: MicroTechAidexHistoryPacket(
                rawBytes: Data([0x23]),
                startTimeOffset: 60,
                records: [MicroTechAidexHistoryRecord(timeOffset: 60, glucose: 120, rawValue: 120)]
            )
        )

        wait(for: [delegate.readingResultsExpectation], timeout: 1)
        XCTAssertEqual(delegate.newDataSampleSyncIdentifiers, ["ABC123-70", "ABC123-60", "ABC123-71"])
        XCTAssertEqual(delegate.newDataSampleSyncIdentifiers.filter { $0 == "ABC123-60" }.count, 1)
        XCTAssertEqual(delegate.noDataCount, 1)
        XCTAssertEqual(manager.emittedHistorySamplesForTesting, Set([60]))
    }

    func testUserRepeatedScanAndConnectionAttemptsDoNotExtendRecoveryDeadline() {
        let bluetoothManager = FakeMicroTechBluetoothManager()
        var scheduled: [(TimeInterval, () -> Void)] = []
        let manager = MicroTechCGMManager(
            state: makeReconnectState(),
            bluetoothManagerFactory: { bluetoothManager },
            reconnectRecoveryScheduler: { scheduled.append(($0, $1)) }
        )

        for _ in 0..<5 {
            _ = manager.scanForSensor()
            manager.fetchNewDataIfNeeded { _ in }
        }

        XCTAssertEqual(scheduled.count, 1)
    }

    func testChangingSensorCancelsRecoveryAndOldTimeoutCannotRebuild() {
        let bluetoothManager = FakeMicroTechBluetoothManager()
        var scheduled: [(TimeInterval, () -> Void)] = []
        let manager = MicroTechCGMManager(
            state: makeReconnectState(),
            bluetoothManagerFactory: { bluetoothManager },
            reconnectRecoveryScheduler: { scheduled.append(($0, $1)) }
        )

        XCTAssertTrue(manager.scanForSensor())
        XCTAssertTrue(manager.configureSensor(deviceName: "LinX-NEW123", sensorSerial: "NEW123"))
        scheduled[0].1()

        XCTAssertEqual(manager.reconnectRecoveryPhaseForTesting, "idle")
        XCTAssertEqual(bluetoothManager.shutdownCallCount, 0)
        XCTAssertEqual(manager.state.sensorSerial, "NEW123")
    }

    func testRegisteredHandshakeBeforeTimeoutCancelsRecoveryAndOldTimeoutDoesNotRebuild() {
        let first = FakeMicroTechBluetoothManager()
        let second = FakeMicroTechBluetoothManager()
        var factoryCalls = 0
        var scheduled: [(TimeInterval, () -> Void)] = []
        let manager = MicroTechCGMManager(
            state: makeReconnectState(),
            bluetoothManagerFactory: {
                factoryCalls += 1
                return factoryCalls == 1 ? first : second
            },
            reconnectRecoveryScheduler: { scheduled.append(($0, $1)) }
        )
        XCTAssertTrue(manager.scanForSensor())
        guard let oldSensor = first.delegate as? MicroTechSensor else {
            return XCTFail("Expected saved sensor delegate")
        }
        manager.microTechSensorDidConnect(oldSensor, session: makeSession())
        XCTAssertTrue(manager.state.hasConnectedSensorSession)
        XCTAssertEqual(manager.reconnectRecoveryPhaseForTesting, "idle")
        scheduled[0].1()

        XCTAssertEqual(factoryCalls, 1)
        XCTAssertEqual(first.shutdownCallCount, 0)
        XCTAssertTrue(second.activatedRemoteIdentifiers.isEmpty)
    }

    func testShuttingDownRejectsOldAndArbitrarySensorHandshakeThenCompletesRebuild() {
        let first = FakeMicroTechBluetoothManager()
        let second = FakeMicroTechBluetoothManager()
        var managers = [first, second]
        var scheduled: [(TimeInterval, () -> Void)] = []
        let manager = MicroTechCGMManager(
            state: makeReconnectState(),
            bluetoothManagerFactory: { managers.removeFirst() },
            reconnectRecoveryScheduler: { scheduled.append(($0, $1)) }
        )
        XCTAssertTrue(manager.scanForSensor())
        guard let oldSensor = first.delegate as? MicroTechSensor else {
            return XCTFail("Expected saved sensor delegate")
        }
        scheduled[0].1()
        XCTAssertEqual(manager.reconnectRecoveryPhaseForTesting, "shuttingDown")
        XCTAssertNil(manager.state.remoteIdentifier)

        let arbitrarySession = makeSession(remoteIdentifier: UUID())
        let arbitrarySensor = makeSensor(session: arbitrarySession)
        manager.microTechSensorDidConnect(oldSensor, session: makeSession())
        manager.microTechSensorDidConnect(arbitrarySensor, session: arbitrarySession)

        XCTAssertEqual(manager.reconnectRecoveryPhaseForTesting, "shuttingDown")
        XCTAssertNil(manager.state.remoteIdentifier)
        XCTAssertEqual(scheduled.count, 1)
        first.completeShutdown()

        XCTAssertEqual(manager.reconnectRecoveryPhaseForTesting, "timing")
        XCTAssertEqual(scheduled.count, 2)
        XCTAssertEqual(second.activatedRemoteIdentifiers, [nil])
    }

    func testQueuedOldSensorRetryRetainsExactSensorPreventingAddressReuseAndCannotAffectReplacement() {
        let first = FakeMicroTechBluetoothManager()
        let second = FakeMicroTechBluetoothManager()
        var managers = [first, second]
        var scheduled: [(TimeInterval, () -> Void)] = []
        var retries: [() -> Void] = []
        let manager = MicroTechCGMManager(
            state: makeReconnectState(),
            bluetoothManagerFactory: { managers.removeFirst() },
            bluetoothRetryScheduler: { retries.append($0) },
            reconnectRecoveryScheduler: { scheduled.append(($0, $1)) }
        )
        XCTAssertTrue(manager.scanForSensor())
        var oldSensor = first.delegate as? MicroTechSensor
        weak let weakOldSensor = oldSensor
        guard oldSensor != nil else {
            return XCTFail("Expected saved sensor delegate")
        }
        manager.microTechSensorDidConnect(oldSensor!, session: makeSession())
        manager.microTechSensorDidDisconnect(oldSensor!)
        XCTAssertEqual(retries.count, 1)
        XCTAssertEqual(scheduled.count, 2)

        scheduled[1].1()
        first.completeShutdown()
        oldSensor = nil
        XCTAssertNotNil(weakOldSensor)
        let replacementScanCount = second.scanRemoteIdentifiers.count

        retries[0]()

        XCTAssertEqual(second.scanRemoteIdentifiers.count, replacementScanCount)
        XCTAssertEqual(scheduled.count, 3)
    }

    func testDeleteBetweenReplacementCreationAndActivationTerminatesReplacement() {
        assertReplacementActivationCancelled { manager in
            manager.delete {}
        }
    }

    func testModeChangeBetweenReplacementCreationAndActivationTerminatesReplacement() {
        assertReplacementActivationCancelled(activationBeforeAction: true) { manager in
            XCTAssertTrue(manager.configureConnectionMode(.broadcast))
        }
    }

    func testRebuildLogsFirstHandshakeAndFirstCurrentReadingOnlyOnce() {
        let first = FakeMicroTechBluetoothManager()
        let second = FakeMicroTechBluetoothManager()
        var managers = [first, second]
        var scheduled: [(TimeInterval, () -> Void)] = []
        var messages: [String] = []
        let manager = MicroTechCGMManager(
            state: makeReconnectState(),
            bluetoothManagerFactory: { managers.removeFirst() },
            reconnectRecoveryScheduler: { scheduled.append(($0, $1)) }
        )
        manager.onboardingDeviceLogHandler = { _, _, message in messages.append(message) }
        XCTAssertTrue(manager.scanForSensor())
        scheduled[0].1()
        first.completeShutdown()
        guard let sensor = second.delegate as? MicroTechSensor else {
            return XCTFail("Expected replacement sensor delegate")
        }
        manager.microTechSensorDidConnect(sensor, session: makeSession(remoteIdentifier: UUID()))
        manager.microTechSensorDidConnect(sensor, session: makeSession(remoteIdentifier: UUID()))
        manager.microTechSensor(sensor, didRead: makeReading(sampleNumber: 100, glucoseMgdl: 120, receivedAt: Date()))
        manager.microTechSensor(sensor, didRead: makeReading(sampleNumber: 101, glucoseMgdl: 121, receivedAt: Date()))

        XCTAssertEqual(messages.filter { $0.contains("recovery cancelled") && $0.contains("handshake") }.count, 1)
        XCTAssertEqual(messages.filter { $0.contains("recoveredAfterReconnect") }.count, 1)
        XCTAssertTrue(messages.contains { $0.contains("60") && $0.contains("rebuild") })
    }

    private func assertReplacementActivationCancelled(
        activationBeforeAction: Bool = false,
        action: (MicroTechCGMManager) -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let first = FakeMicroTechBluetoothManager()
        let second = FakeMicroTechBluetoothManager()
        second.deferActivations = true
        var managers = [first, second]
        var scheduled: [(TimeInterval, () -> Void)] = []
        let manager = MicroTechCGMManager(
            state: makeReconnectState(),
            bluetoothManagerFactory: { managers.removeFirst() },
            reconnectRecoveryScheduler: { scheduled.append(($0, $1)) }
        )
        XCTAssertTrue(manager.scanForSensor(), file: file, line: line)
        scheduled[0].1()
        first.completeShutdown()
        if activationBeforeAction {
            second.runDeferredActivations()
            XCTAssertTrue(second.isScanning, file: file, line: line)
            action(manager)
        } else {
            action(manager)
            second.runDeferredActivations()
        }

        XCTAssertNil(first.delegate, file: file, line: line)
        XCTAssertNil(first.logHandler, file: file, line: line)
        XCTAssertFalse(first.isScanning, file: file, line: line)
        XCTAssertNil(second.delegate, file: file, line: line)
        XCTAssertNil(second.logHandler, file: file, line: line)
        XCTAssertFalse(second.isScanning, file: file, line: line)
        XCTAssertEqual(second.shutdownCallCount, 1, file: file, line: line)
    }

    private func makeReconnectState() -> MicroTechCGMManagerState {
        var state = MicroTechCGMManagerState()
        state.remoteIdentifier = UUID(uuidString: "00000000-0000-0000-0000-000000000123")!
        state.deviceName = "LinX-ABC123"
        state.sensorSerial = "ABC123"
        state.activationTime = Date(timeIntervalSince1970: 1_699_900_000)
        state.lastReadingDate = Date(timeIntervalSince1970: 1_700_000_000)
        state.latestReading = makeReading(sampleNumber: 42, glucoseMgdl: 123, receivedAt: state.lastReadingDate!)
        state.latestSampleNumber = 42
        state.hasConnectedSensorSession = true
        state.connectionMode = .direct
        return state
    }

    private func assertSynchronousWriteFailure(
        _ entries: [MicroTechGattLogEntry],
        payload: Data,
        expectedError: MicroTechPeripheralManagerError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(entries.count, 1, file: file, line: line)
        guard let entry = entries.first else {
            return
        }
        XCTAssertEqual(entry.type, .error, file: file, line: line)
        XCTAssertTrue(entry.message.contains("operation=write event=failed"), file: file, line: line)
        XCTAssertFalse(entry.message.contains("event=attempted"), file: file, line: line)
        XCTAssertTrue(entry.message.contains("writeType=withResponse"), file: file, line: line)
        XCTAssertTrue(entry.message.contains("payloadLength=64"), file: file, line: line)
        XCTAssertTrue(
            entry.message.contains("payloadHex=\(payload.microTechHexadecimalString)"),
            file: file,
            line: line
        )
        XCTAssertTrue(entry.message.contains("errorDomain="), file: file, line: line)
        XCTAssertTrue(entry.message.contains("errorCode="), file: file, line: line)
        XCTAssertTrue(entry.message.contains(MicroTechDiagnosticLog.errorFields(expectedError)), file: file, line: line)
    }

    private func assertDisconnectCompletesPendingOperation(
        _ operation: MicroTechGattOperation,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let state = MicroTechGattOperationState()
        let waitStarted = DispatchSemaphore(value: 0)
        let waitCompleted = expectation(description: "\(operation.name) completed after disconnect")
        let outcome = ThreadSafeWaitOutcome()
        try state.begin(operation)

        DispatchQueue.global().async {
            waitStarted.signal()
            outcome.capture {
                try state.wait(
                    timeout: 0.2,
                    onTimeout: { outcome.recordTimeout() }
                )
            }
            waitCompleted.fulfill()
        }

        XCTAssertEqual(waitStarted.wait(timeout: .now() + 1), .success, file: file, line: line)
        XCTAssertTrue(state.requestDisconnect(), file: file, line: line)
        wait(for: [waitCompleted], timeout: 1)
        XCTAssertEqual(outcome.error as? MicroTechPeripheralManagerError, .notConnected, file: file, line: line)
        XCTAssertEqual(outcome.timeoutCount, 0, file: file, line: line)
        XCTAssertFalse(state.requestDisconnect(), file: file, line: line)
    }

    private func assertGattErrorLog(
        callback: MicroTechGattCallback,
        service: CBUUID?,
        characteristic: CBUUID?,
        operation: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let identifier = UUID(uuidString: "00000000-0000-0000-0000-000000000123")!
        let error = NSError(
            domain: "CoreBluetooth",
            code: 17,
            userInfo: [NSLocalizedDescriptionKey: "callback failure"]
        )
        let state = MicroTechGattOperationState()
        var entries: [MicroTechGattLogEntry] = []

        switch callback {
        case .read:
            guard let characteristic else {
                return XCTFail("Read callback requires characteristic", file: file, line: line)
            }
            XCTAssertNoThrow(try state.begin(.read(characteristic)), file: file, line: line)
            state.handleValueCallback(
                identifier: identifier,
                characteristic: characteristic,
                error: error,
                value: nil,
                log: { entries.append(contentsOf: $0.entries) }
            )
        case .notificationValue:
            guard let characteristic else {
                return XCTFail("Notification callback requires characteristic", file: file, line: line)
            }
            state.handleValueCallback(
                identifier: identifier,
                characteristic: characteristic,
                error: error,
                value: nil,
                log: { entries.append(contentsOf: $0.entries) }
            )
        case .discoverServices, .discoverCharacteristics, .notificationState, .write:
            let pendingOperation: MicroTechGattOperation?
            switch callback {
            case .discoverServices:
                pendingOperation = service.map(MicroTechGattOperation.discoverServices)
            case .discoverCharacteristics:
                pendingOperation = service.map(MicroTechGattOperation.discoverCharacteristics)
            case .notificationState:
                pendingOperation = characteristic.map(MicroTechGattOperation.notification)
            case .write:
                pendingOperation = characteristic.map(MicroTechGattOperation.write)
            case .read, .notificationValue:
                pendingOperation = nil
            }
            guard let pendingOperation else {
                return XCTFail("Callback requires pending operation", file: file, line: line)
            }
            XCTAssertNoThrow(try state.begin(pendingOperation), file: file, line: line)
            state.handleOperationCallback(
                callback: callback,
                identifier: identifier,
                service: service,
                characteristic: characteristic,
                error: error,
                log: { entries.append(contentsOf: $0.entries) }
            )
        }

        XCTAssertEqual(entries.count, 1, file: file, line: line)
        XCTAssertEqual(entries.first?.type, .error, file: file, line: line)
        XCTAssertEqual(
            entries.first?.message,
            "stage=gatt operation=\(operation) event=failed identifier=\(identifier) service=\(service?.uuidString ?? "nil") characteristic=\(characteristic?.uuidString ?? "nil") errorDomain=CoreBluetooth errorCode=17 errorDescription=callback failure",
            file: file,
            line: line
        )
    }

    private func makeReading(
        sampleNumber: Int,
        glucoseMgdl: Int,
        receivedAt: Date,
        quality: Int = 0,
        sensorSerial: String = "ABC123",
        rawBytes: Data = Data([0x01])
    ) -> MicroTechGlucoseReading {
        let packet = MicroTechAidexCurrentPacket(
            rawBytes: rawBytes,
            packetType: 0x01,
            trend: -1,
            timeOffset: sampleNumber,
            glucoseRaw: glucoseMgdl,
            glucose: glucoseMgdl,
            quality: quality,
            i1: 0,
            i2: 0,
            vc: 0,
            status: 0,
            byte14Flag: 0
        )
        return MicroTechGlucoseReading(
            current: packet,
            sensorSerial: sensorSerial,
            receivedAt: receivedAt
        )
    }

    private func makeSession(
        remoteIdentifier: UUID = UUID(uuidString: "00000000-0000-0000-0000-000000000123")!,
        deviceName: String = "LinX-ABC123",
        sensorSerial: String = "ABC123"
    ) -> MicroTechAidexSession {
        MicroTechAidexSession(
            remoteIdentifier: remoteIdentifier,
            deviceName: deviceName,
            sensorSerial: sensorSerial
        )
    }

    private func makeSensor(session: MicroTechAidexSession) -> MicroTechSensor {
        MicroTechSensor(
            session: session,
            peripheralSession: FakeMicroTechPeripheralSession(
                deviceIdentifier: session.remoteIdentifier,
                deviceName: session.deviceName,
                f002Challenge: Data()
            ),
            pairingKeyTimeout: 0
        )
    }

    private func encryptedChallenge(for material: MicroTechAidexKeyMaterial) throws -> Data {
        try MicroTechAidexCrypto.encryptCfb128(key: material.key, iv: material.iv, plain: material.key)
    }

    private func microTechPluginBundle(
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Bundle {
        let bundleURL = Bundle(for: type(of: self))
            .bundleURL
            .deletingLastPathComponent()
            .appendingPathComponent("MicroTechCGMPlugin.loopplugin")
        guard let bundle = Bundle(url: bundleURL) else {
            XCTFail("Expected MicroTechCGMPlugin.loopplugin at \(bundleURL.path)", file: file, line: line)
            return Bundle(for: type(of: self))
        }
        return bundle
    }

    private static let mgdlUnit = HKUnit
        .gramUnit(with: .milli)
        .unitDivided(by: .literUnit(with: .deci))
}

private final class TestCGMManagerDelegate: CGMManagerDelegate {
    let readingResultsExpectation: XCTestExpectation
    var startDateForFiltering: Date?
    private(set) var readingResults: [CGMReadingResult] = []
    private(set) var loggedEvents: [(deviceIdentifier: String?, type: DeviceLogEntryType, message: String)] = []

    init(expectedReadingResultCount: Int) {
        readingResultsExpectation = XCTestExpectation(description: "reading results")
        readingResultsExpectation.expectedFulfillmentCount = max(expectedReadingResultCount, 1)
        readingResultsExpectation.isInverted = expectedReadingResultCount == 0
    }

    var newDataSampleSyncIdentifiers: [String] {
        newDataSamples.map(\.syncIdentifier)
    }

    var newDataSamples: [NewGlucoseSample] {
        readingResults.flatMap { result -> [NewGlucoseSample] in
            if case .newData(let samples) = result {
                return samples
            }
            return []
        }
    }

    var noDataCount: Int {
        readingResults.filter { result in
            if case .noData = result {
                return true
            }
            return false
        }.count
    }

    func startDateToFilterNewData(for manager: CGMManager) -> Date? {
        startDateForFiltering
    }

    func cgmManager(_ manager: CGMManager, hasNew readingResult: CGMReadingResult) {
        readingResults.append(readingResult)
        readingResultsExpectation.fulfill()
    }

    func cgmManager(_ manager: CGMManager, hasNew events: [PersistedCgmEvent]) {
    }

    func cgmManagerWantsDeletion(_ manager: CGMManager) {
    }

    func cgmManagerDidUpdateState(_ manager: CGMManager) {
    }

    func credentialStoragePrefix(for manager: CGMManager) -> String {
        "MicroTechCGMManagerTests"
    }

    func cgmManager(_ manager: CGMManager, didUpdate status: CGMManagerStatus) {
    }

    func deviceManager(
        _ manager: DeviceManager,
        logEventForDeviceIdentifier deviceIdentifier: String?,
        type: DeviceLogEntryType,
        message: String,
        completion: ((Error?) -> Void)?
    ) {
        loggedEvents.append((deviceIdentifier: deviceIdentifier, type: type, message: message))
        completion?(nil)
    }

    func issueAlert(_ alert: LoopKit.Alert) {
    }

    func retractAlert(identifier: LoopKit.Alert.Identifier) {
    }

    func doesIssuedAlertExist(identifier: LoopKit.Alert.Identifier, completion: @escaping (Result<Bool, Error>) -> Void) {
        completion(.success(false))
    }

    func lookupAllUnretracted(
        managerIdentifier: String,
        completion: @escaping (Result<[PersistedAlert], Error>) -> Void
    ) {
        completion(.success([]))
    }

    func lookupAllUnacknowledgedUnretracted(
        managerIdentifier: String,
        completion: @escaping (Result<[PersistedAlert], Error>) -> Void
    ) {
        completion(.success([]))
    }

    func recordRetractedAlert(_ alert: LoopKit.Alert, at date: Date) {
    }
}

private final class TestCGMStatusObserver: CGMManagerStatusObserver {
    let statusExpectation: XCTestExpectation
    private(set) var statuses: [CGMManagerStatus] = []

    init(expectedStatusCount: Int) {
        statusExpectation = XCTestExpectation(description: "cgm status updates")
        statusExpectation.expectedFulfillmentCount = max(expectedStatusCount, 1)
        statusExpectation.isInverted = expectedStatusCount == 0
    }

    func cgmManager(_ manager: CGMManager, didUpdate status: CGMManagerStatus) {
        statuses.append(status)
        statusExpectation.fulfill()
    }
}

private final class TestCGMOnboardingDelegate: CGMManagerOnboardingDelegate {
    let createdExpectation: XCTestExpectation
    let onboardedExpectation: XCTestExpectation
    private(set) var createdManagers: [CGMManagerUI] = []
    private(set) var onboardedManagers: [CGMManagerUI] = []

    init(expectedCreateCount: Int, expectedOnboardCount: Int) {
        createdExpectation = XCTestExpectation(description: "created cgm managers")
        createdExpectation.expectedFulfillmentCount = max(expectedCreateCount, 1)
        createdExpectation.isInverted = expectedCreateCount == 0
        onboardedExpectation = XCTestExpectation(description: "onboarded cgm managers")
        onboardedExpectation.expectedFulfillmentCount = max(expectedOnboardCount, 1)
        onboardedExpectation.isInverted = expectedOnboardCount == 0
    }

    func cgmManagerOnboarding(didCreateCGMManager cgmManager: CGMManagerUI) {
        createdManagers.append(cgmManager)
        createdExpectation.fulfill()
    }

    func cgmManagerOnboarding(didOnboardCGMManager cgmManager: CGMManagerUI) {
        onboardedManagers.append(cgmManager)
        onboardedExpectation.fulfill()
    }
}

private final class FakeMicroTechBluetoothManager: MicroTechBluetoothManaging {
    weak var delegate: MicroTechBluetoothManagerDelegate?
    var logHandler: ((String, MicroTechBluetoothLogType) -> Void)?
    var scanLog: (message: String, type: MicroTechBluetoothLogType)?
    var isScanning = false
    var isConnectedReadCount = 0
    private var storedIsConnected = false
    var isConnected: Bool {
        get {
            isConnectedReadCount += 1
            return storedIsConnected
        }
        set {
            storedIsConnected = newValue
        }
    }
    private(set) var scanRemoteIdentifiers: [UUID?] = []
    private(set) var refreshConnectedPeripheralCallCount = 0
    private(set) var disconnectCallCount = 0
    private(set) var forgetPeripheralCallCount = 0
    private(set) var shutdownCallCount = 0
    private var shutdownCompletions: [() -> Void] = []
    private(set) var activatedRemoteIdentifiers: [UUID?] = []
    var deferActivations = false
    private var deferredActivations: [() -> Void] = []

    func activateDirectScan(
        delegate: MicroTechBluetoothManagerDelegate,
        logHandler: @escaping (String, MicroTechBluetoothLogType) -> Void,
        remoteIdentifier: UUID?
    ) {
        let activation = { [weak self, weak delegate] in
            guard let self, let delegate, self.shutdownCallCount == 0 else {
                return
            }
            self.delegate = delegate
            self.logHandler = logHandler
            self.isScanning = true
            self.activatedRemoteIdentifiers.append(remoteIdentifier)
            self.scanRemoteIdentifiers.append(remoteIdentifier)
        }
        if deferActivations {
            deferredActivations.append(activation)
        } else {
            activation()
        }
    }

    func runDeferredActivations() {
        let activations = deferredActivations
        deferredActivations.removeAll()
        activations.forEach { $0() }
    }

    func scan(remoteIdentifier: UUID?) {
        isScanning = true
        scanRemoteIdentifiers.append(remoteIdentifier)
        if let scanLog {
            logHandler?(scanLog.message, scanLog.type)
        }
    }

    func refreshConnectedPeripheral() {
        refreshConnectedPeripheralCallCount += 1
    }

    func disconnect() {
        isScanning = false
        isConnected = false
        disconnectCallCount += 1
    }

    func forgetPeripheral() {
        forgetPeripheralCallCount += 1
    }

    func shutdown(completion: @escaping () -> Void) {
        shutdownCallCount += 1
        isScanning = false
        isConnected = false
        delegate = nil
        logHandler = nil
        shutdownCompletions.append(completion)
    }

    func completeShutdown(at index: Int = 0) {
        shutdownCompletions.remove(at: index)()
    }
}

private final class ReentrantLogHandlerMicroTechBluetoothManager: MicroTechBluetoothManaging {
    weak var delegate: MicroTechBluetoothManagerDelegate?
    var onSetLogHandler: ((((String, MicroTechBluetoothLogType) -> Void)?) -> Void)?
    var logHandler: ((String, MicroTechBluetoothLogType) -> Void)? {
        didSet {
            onSetLogHandler?(logHandler)
        }
    }
    var isScanning = false
    var isConnected = false
    private(set) var shutdownCallCount = 0
    private var shutdownCompletions: [() -> Void] = []

    func scan(remoteIdentifier: UUID?) {
        isScanning = true
    }

    func refreshConnectedPeripheral() {}
    func disconnect() {}
    func forgetPeripheral() {}

    func shutdown(completion: @escaping () -> Void) {
        shutdownCallCount += 1
        shutdownCompletions.append(completion)
    }

    func completeShutdown(at index: Int = 0) {
        shutdownCompletions.remove(at: index)()
    }
}

private final class ShutdownBluetoothManagerDelegate: MicroTechBluetoothManagerDelegate {
    private(set) var callbackCount = 0

    func microTechBluetoothManager(
        _ manager: MicroTechBluetoothManager,
        shouldConnectToDeviceName deviceName: String,
        identifier: UUID
    ) -> Bool {
        callbackCount += 1
        return true
    }

    func microTechBluetoothManager(
        _ manager: MicroTechBluetoothManager,
        didReady peripheralSession: MicroTechPeripheralSession
    ) {
        callbackCount += 1
    }

    func microTechBluetoothManager(
        _ manager: MicroTechBluetoothManager,
        didReceive value: Data,
        for characteristic: CBUUID,
        session: MicroTechPeripheralSession
    ) {
        callbackCount += 1
    }

    func microTechBluetoothManager(
        _ manager: MicroTechBluetoothManager,
        didDisconnect session: MicroTechPeripheralSession
    ) {
        callbackCount += 1
    }

    func microTechBluetoothManager(
        _ manager: MicroTechBluetoothManager,
        didDiscoverBroadcast advertisement: MicroTechBroadcastAdvertisement
    ) {
        callbackCount += 1
    }

    func microTechBluetoothManager(_ manager: MicroTechBluetoothManager, didFailWith error: Error) {
        callbackCount += 1
    }
}

private final class ShutdownPeripheralManagerDelegate: MicroTechPeripheralManagerDelegate {
    private(set) var callbackCount = 0

    func microTechPeripheralManager(
        _ manager: MicroTechPeripheralManager,
        didUpdateValue value: Data,
        for characteristic: CBUUID
    ) {
        callbackCount += 1
    }

    func microTechPeripheralManager(_ manager: MicroTechPeripheralManager, didDisconnectWith error: Error?) {
        callbackCount += 1
    }
}

private enum ShutdownTestError: Error {
    case forcedFailure
}

private final class SpyMicroTechConnectionTimeoutController: MicroTechConnectionTimeoutControlling {
    private(set) var scheduledIdentifiers: Set<UUID>
    private(set) var cancelCallCount = 0
    private(set) var cancelAllCallCount = 0
    private let onCancelAll: (() -> Void)?

    init(scheduledIdentifiers: Set<UUID> = [], onCancelAll: (() -> Void)? = nil) {
        self.scheduledIdentifiers = scheduledIdentifiers
        self.onCancelAll = onCancelAll
    }

    func schedule(identifier: UUID, handler: @escaping (UUID) -> Void) {
        scheduledIdentifiers.insert(identifier)
    }

    func cancel(identifier: UUID) {
        cancelCallCount += 1
        scheduledIdentifiers.remove(identifier)
    }

    func cancelAll() {
        cancelAllCallCount += 1
        scheduledIdentifiers.removeAll()
        onCancelAll?()
    }
}

private final class FakeManagedMicroTechPeripheralManager: MicroTechManagedPeripheral {
    weak var delegate: MicroTechPeripheralManagerDelegate?
    var willCancelConnection: ((UUID) -> Void)?
    let deviceIdentifier: UUID
    private(set) var deviceName: String
    var isConnected: Bool
    private(set) var configureCallCount = 0
    private(set) var disconnectCallCount = 0
    private(set) var didDisconnectCallCount = 0

    init(deviceIdentifier: UUID, deviceName: String, isConnected: Bool) {
        self.deviceIdentifier = deviceIdentifier
        self.deviceName = deviceName
        self.isConnected = isConnected
    }

    func updateAdvertisedName(_ advertisedName: String?) {
        if let advertisedName {
            deviceName = advertisedName
        }
    }

    func configure() throws {
        configureCallCount += 1
    }

    func subscribe(_ characteristic: CBUUID) throws {}
    func write(_ value: Data, to characteristic: CBUUID) throws {}
    func read(_ characteristic: CBUUID) throws -> Data { Data() }

    func disconnect() {
        disconnectCallCount += 1
        isConnected = false
    }

    func didDisconnect(error: Error?) {
        didDisconnectCallCount += 1
        isConnected = false
    }
}

private final class FakeRestoredMicroTechPeripheralReference: MicroTechRestoredPeripheralReference {
    let identifier: UUID
    let name: String?
    var peripheral: CBPeripheral? { nil }

    init(identifier: UUID, name: String?) {
        self.identifier = identifier
        self.name = name
    }
}

private final class ThreadSafeMessages {
    private let lock = NSLock()
    private var messages: [String] = []

    var values: [String] {
        lock.lock()
        defer { lock.unlock() }
        return messages
    }

    func append(_ message: String) {
        lock.lock()
        defer { lock.unlock() }
        messages.append(message)
    }
}

private final class ThreadSafeWaitOutcome {
    private let lock = NSLock()
    private var storedResult: MicroTechGattWaitResult?
    private var storedError: Error?
    private var storedTimeoutCount = 0

    var waitResult: MicroTechGattWaitResult? {
        lock.lock()
        defer { lock.unlock() }
        return storedResult
    }

    var error: Error? {
        lock.lock()
        defer { lock.unlock() }
        return storedError
    }

    var timeoutCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedTimeoutCount
    }

    func capture(_ work: () throws -> MicroTechGattWaitResult) {
        let outcome: Result<MicroTechGattWaitResult, Error>
        do {
            outcome = .success(try work())
        } catch {
            outcome = .failure(error)
        }
        lock.lock()
        defer { lock.unlock() }
        switch outcome {
        case .success(let result):
            storedResult = result
        case .failure(let error):
            storedError = error
        }
    }

    func recordTimeout() {
        lock.lock()
        storedTimeoutCount += 1
        lock.unlock()
    }
}

private enum MicroTechCGMManagerTestError: Error {
    case poweredOff
}
