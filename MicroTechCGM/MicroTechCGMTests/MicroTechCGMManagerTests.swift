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
        manager.microTechSensorDidConnect(makeSensor(session: session), session: session)

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

        manager.microTechSensorDidConnect(sensor, session: session)
        manager.microTechSensor(sensor, didRead: makeReading(sampleNumber: 42, glucoseMgdl: 123, receivedAt: readingDate))

        wait(for: [delegate.readingResultsExpectation], timeout: 1)
        XCTAssertEqual(manager.state.sensorSerial, "ABC123")
        XCTAssertEqual(manager.state.deviceName, "LinX-ABC123")
        XCTAssertEqual(manager.state.latestSampleNumber, 42)
        XCTAssertEqual(delegate.newDataSampleSyncIdentifiers, ["ABC123-42"])
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
                event.message.contains("notification F003 decrypted type=0x03") &&
                event.message.contains("rawPrefix=030100FE60545F80B303800C4500004D5B")
        })
        XCTAssertTrue(delegate.loggedEvents.contains { event in
            event.type == .receive &&
                event.message.contains("parsed current packetType=0x03") &&
                event.message.contains("sample=21600") &&
                event.message.contains("rawPrefix=030100FE60545F80B303800C4500004D5B")
        })
        XCTAssertTrue(delegate.loggedEvents.contains { event in
            event.type == .receive &&
                event.message.contains("current accepted serial=ABC123 sample=21600") &&
                event.message.contains("packetType=0x03") &&
                event.message.contains("rawPrefix=030100FE60545F80B303800C4500004D5B")
        })
    }

    func testStatusObserverReceivesSensorSessionAndReadingUpdates() throws {
        let manager = MicroTechCGMManager()
        let observer = TestCGMStatusObserver(expectedStatusCount: 2)
        let statusQueue = DispatchQueue(label: "MicroTechCGMManagerTests.statusObserver")
        let session = makeSession()
        let sensor = makeSensor(session: session)

        manager.addStatusObserver(observer, queue: statusQueue)
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

    func testRepeatedSensorErrorsDisconnectToRestartBluetooth() throws {
        let remoteIdentifier = UUID(uuidString: "00000000-0000-0000-0000-000000000123")!
        var state = MicroTechCGMManagerState()
        state.remoteIdentifier = remoteIdentifier
        state.deviceName = "LinX-ABC123"
        state.sensorSerial = "ABC123"
        let bluetoothManager = FakeMicroTechBluetoothManager()
        bluetoothManager.isConnected = true
        var retryBlocks: [() -> Void] = []
        let manager = MicroTechCGMManager(
            state: state,
            bluetoothManagerFactory: { bluetoothManager },
            bluetoothRetryScheduler: { retryBlocks.append($0) }
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
        XCTAssertTrue(peripheralSession.calls.contains(.write(expectedHistoryCommand, MicroTechAidexProfile.f002UUID.uuidString)))
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

        manager.microTechSensorDidConnect(sensorA, session: sessionA)
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

        manager.microTechSensorDidConnect(sensorA, session: sessionA)
        manager.microTechSensor(sensorA, didRead: readingA)
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

        manager.microTechSensorDidConnect(sensorA, session: sessionA)
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

    func testPeripheralDisconnectingStateSchedulesConnectionTimeout() {
        XCTAssertFalse(MicroTechBluetoothManager.shouldScheduleConnectionTimeout(for: .connected))
        XCTAssertTrue(MicroTechBluetoothManager.shouldScheduleConnectionTimeout(for: .disconnected))
        XCTAssertTrue(MicroTechBluetoothManager.shouldScheduleConnectionTimeout(for: .connecting))
        XCTAssertTrue(MicroTechBluetoothManager.shouldScheduleConnectionTimeout(for: .disconnecting))
    }

    func testBluetoothRestoreIdentifierIsStableForBackgroundRecovery() {
        XCTAssertEqual(MicroTechBluetoothManager.restoreIdentifier, "com.loopkit.MicroTechCGM")
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

    private func makeReading(
        sampleNumber: Int,
        glucoseMgdl: Int,
        receivedAt: Date,
        quality: Int = 0,
        sensorSerial: String = "ABC123"
    ) -> MicroTechGlucoseReading {
        let packet = MicroTechAidexCurrentPacket(
            rawBytes: Data([0x01]),
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

    func scan(remoteIdentifier: UUID?) {
        isScanning = true
        scanRemoteIdentifiers.append(remoteIdentifier)
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
}

private enum MicroTechCGMManagerTestError: Error {
    case poweredOff
}
