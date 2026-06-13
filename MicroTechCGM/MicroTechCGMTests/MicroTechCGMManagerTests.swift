import HealthKit
import LoopKit
import LoopKitUI
import XCTest
@testable import MicroTechCGM
@testable import MicroTechCGMUI

final class MicroTechCGMManagerTests: XCTestCase {
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

    func testScanForSensorRequiresSensorSerial() {
        var didCreateBluetoothManager = false
        let manager = MicroTechCGMManager(
            state: MicroTechCGMManagerState(),
            bluetoothManagerFactory: {
                didCreateBluetoothManager = true
                return FakeMicroTechBluetoothManager()
            }
        )

        XCTAssertFalse(manager.scanForSensor())
        XCTAssertFalse(didCreateBluetoothManager)
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

    func testSensorHistoryReadDoesNotChangeLatestSampleNumberOrEmitNewGlucoseSample() throws {
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
        XCTAssertEqual(delegate.newDataSampleSyncIdentifiers, ["ABC123-42"])
        XCTAssertEqual(delegate.noDataCount, 1)
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
        let sensor = MicroTechSensor(session: session, peripheralSession: peripheralSession)
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
            )
        )
    }

    private func encryptedChallenge(for material: MicroTechAidexKeyMaterial) throws -> Data {
        try MicroTechAidexCrypto.encryptCfb128(key: material.key, iv: material.iv, plain: material.key)
    }

    private static let mgdlUnit = HKUnit
        .gramUnit(with: .milli)
        .unitDivided(by: .literUnit(with: .deci))
}

private final class TestCGMManagerDelegate: CGMManagerDelegate {
    let readingResultsExpectation: XCTestExpectation
    private(set) var readingResults: [CGMReadingResult] = []

    init(expectedReadingResultCount: Int) {
        readingResultsExpectation = XCTestExpectation(description: "reading results")
        readingResultsExpectation.expectedFulfillmentCount = max(expectedReadingResultCount, 1)
        readingResultsExpectation.isInverted = expectedReadingResultCount == 0
    }

    var newDataSampleSyncIdentifiers: [String] {
        readingResults.flatMap { result -> [String] in
            if case .newData(let samples) = result {
                return samples.map(\.syncIdentifier)
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
        nil
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
        completion?(nil)
    }

    func issueAlert(_ alert: Alert) {
    }

    func retractAlert(identifier: Alert.Identifier) {
    }

    func doesIssuedAlertExist(identifier: Alert.Identifier, completion: @escaping (Result<Bool, Error>) -> Void) {
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

    func recordRetractedAlert(_ alert: Alert, at date: Date) {
    }
}

private final class FakeMicroTechBluetoothManager: MicroTechBluetoothManaging {
    weak var delegate: MicroTechBluetoothManagerDelegate?
    var isScanning = false
    var isConnected = false
    private(set) var scanRemoteIdentifiers: [UUID?] = []
    private(set) var disconnectCallCount = 0
    private(set) var forgetPeripheralCallCount = 0

    func scan(remoteIdentifier: UUID?) {
        isScanning = true
        scanRemoteIdentifiers.append(remoteIdentifier)
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
