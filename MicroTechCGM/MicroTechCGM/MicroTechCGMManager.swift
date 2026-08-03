import CoreBluetooth
import Foundation
import HealthKit
import LoopKit
import os.log

public typealias MicroTechOnboardingDeviceLogHandler = (
    _ deviceIdentifier: String?,
    _ type: DeviceLogEntryType,
    _ message: String
) -> Void

public final class MicroTechCGMManager: CGMManager {
    private let lockedManagerState: Locked<MicroTechCGMManagerProtectedState>
    private let delegate = WeakSynchronizedDelegate<CGMManagerDelegate>()
    private let deviceLogDestination = Locked<MicroTechDeviceLogDestination>(.systemOnly)
    private let statusObservers = WeakSynchronizedSet<CGMManagerStatusObserver>()
    private let delegateQueueSpecificKey = DispatchSpecificKey<UUID>()
    private let delegateQueueSpecificValue = UUID()
    private let bluetoothManagerFactory: () -> MicroTechBluetoothManaging
    private let bluetoothRetryScheduler: (@escaping () -> Void) -> Void
    private let reconnectRecoveryScheduler: (TimeInterval, @escaping () -> Void) -> Void
    private let staleConnectionScheduler: (TimeInterval, @escaping () -> Void) -> Void
    private let sensorStartScheduler: (@escaping () -> Void) -> Void
    private let beforeSensorStart: () -> Void
    private let callbackProcessingBarrier: () -> Void
    private let dateProvider: () -> Date
    private let resumeScanWhenDelegateQueueConfigured: Bool
    private var didResumeScanWhenDelegateQueueConfigured = false
    private let log = OSLog(category: "MicroTechCGMManager")

    public static let pluginIdentifier = "MicroTechLinXCGMManager"

    public let localizedTitle = "MicroTech LinX"
    public let isOnboarded = true
    public let providesBLEHeartbeat = false

    public var state: MicroTechCGMManagerState {
        lockedManagerState.value.state
    }

    public weak var cgmManagerDelegate: CGMManagerDelegate? {
        get {
            delegate.delegate
        }
        set {
            deviceLogDestination.mutate { destination in
                delegate.delegate = newValue
                destination = newValue == nil ? .systemOnly : .formalDelegate
            }
        }
    }

    public var onboardingDeviceLogHandler: MicroTechOnboardingDeviceLogHandler? {
        get {
            if case .onboarding(let handler) = deviceLogDestination.value {
                return handler
            }
            return nil
        }
        set {
            deviceLogDestination.mutate { destination in
                guard delegate.delegate == nil else {
                    destination = .formalDelegate
                    return
                }
                destination = newValue.map(MicroTechDeviceLogDestination.onboarding) ?? .systemOnly
            }
        }
    }

    public var delegateQueue: DispatchQueue! {
        get {
            delegate.queue
        }
        set {
            delegate.queue = newValue
            registerDelegateQueue(delegate.queue)
            resumeSavedSensorScanAfterDelegateQueueConfiguredIfNeeded()
        }
    }

    public var managedDataInterval: TimeInterval? {
        TimeInterval(3 * 60 * 60)
    }

    public var uploadReadings: Bool {
        get {
            state.uploadReadings
        }
        set {
            mutateState { state in
                state.uploadReadings = newValue
            }
        }
    }

    public var shouldSyncToRemoteService: Bool {
        state.uploadReadings
    }

    public var isScanning: Bool {
        let manager = readProtectedState { $0.bluetoothManager?.manager }
        return manager?.isScanning == true
    }

    public var isConnected: Bool {
        let manager = readProtectedState { $0.bluetoothManager?.manager }
        return manager?.isConnected == true
    }

    public var glucoseDisplay: GlucoseDisplayable? {
        state.latestReading
    }

    public var cgmManagerStatus: CGMManagerStatus {
        let state = self.state
        return CGMManagerStatus(
            hasValidSensorSession: state.hasConnectedSensorSession,
            lastCommunicationDate: state.lastReadingDate,
            device: device(for: state)
        )
    }

    public init() {
        bluetoothManagerFactory = { MicroTechBluetoothManager(initialConnectionMode: .direct) }
        bluetoothRetryScheduler = { retry in
            DispatchQueue.global(qos: .utility).async(execute: retry)
        }
        reconnectRecoveryScheduler = { delay, recovery in
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + delay, execute: recovery)
        }
        staleConnectionScheduler = { delay, watchdog in
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + delay, execute: watchdog)
        }
        sensorStartScheduler = { start in
            DispatchQueue.global(qos: .utility).async(execute: start)
        }
        beforeSensorStart = {}
        callbackProcessingBarrier = {}
        dateProvider = { Date() }
        resumeScanWhenDelegateQueueConfigured = false
        lockedManagerState = Locked(MicroTechCGMManagerProtectedState(state: MicroTechCGMManagerState()))
        registerDelegateQueue(delegate.queue)
    }

    init(
        state: MicroTechCGMManagerState,
        bluetoothManagerFactory: (() -> MicroTechBluetoothManaging)? = nil,
        bluetoothRetryScheduler: @escaping (@escaping () -> Void) -> Void = { retry in
            DispatchQueue.global(qos: .utility).async(execute: retry)
        },
        reconnectRecoveryScheduler: @escaping (TimeInterval, @escaping () -> Void) -> Void = { delay, recovery in
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + delay, execute: recovery)
        },
        staleConnectionScheduler: @escaping (TimeInterval, @escaping () -> Void) -> Void = { delay, watchdog in
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + delay, execute: watchdog)
        },
        sensorStartScheduler: @escaping (@escaping () -> Void) -> Void = { start in
            DispatchQueue.global(qos: .utility).async(execute: start)
        },
        beforeSensorStart: @escaping () -> Void = {},
        resumeScanWhenDelegateQueueConfigured: Bool = false,
        dateProvider: @escaping () -> Date = { Date() },
        callbackProcessingBarrier: @escaping () -> Void = {}
    ) {
        self.bluetoothManagerFactory = bluetoothManagerFactory ?? {
            MicroTechBluetoothManager(initialConnectionMode: state.connectionMode)
        }
        self.bluetoothRetryScheduler = bluetoothRetryScheduler
        self.reconnectRecoveryScheduler = reconnectRecoveryScheduler
        self.staleConnectionScheduler = staleConnectionScheduler
        self.sensorStartScheduler = sensorStartScheduler
        self.beforeSensorStart = beforeSensorStart
        self.callbackProcessingBarrier = callbackProcessingBarrier
        self.dateProvider = dateProvider
        self.resumeScanWhenDelegateQueueConfigured = resumeScanWhenDelegateQueueConfigured
        lockedManagerState = Locked(MicroTechCGMManagerProtectedState(state: state))
        registerDelegateQueue(delegate.queue)
    }

    public required init?(rawState: RawStateValue) {
        let restoredState = MicroTechCGMManagerState(rawValue: rawState)
        bluetoothManagerFactory = {
            MicroTechBluetoothManager(initialConnectionMode: restoredState.connectionMode)
        }
        bluetoothRetryScheduler = { retry in
            DispatchQueue.global(qos: .utility).async(execute: retry)
        }
        reconnectRecoveryScheduler = { delay, recovery in
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + delay, execute: recovery)
        }
        staleConnectionScheduler = { delay, watchdog in
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + delay, execute: watchdog)
        }
        sensorStartScheduler = { start in
            DispatchQueue.global(qos: .utility).async(execute: start)
        }
        beforeSensorStart = {}
        callbackProcessingBarrier = {}
        dateProvider = { Date() }
        resumeScanWhenDelegateQueueConfigured = restoredState.sensorSerial?.isEmpty == false
        lockedManagerState = Locked(MicroTechCGMManagerProtectedState(state: restoredState))
        registerDelegateQueue(delegate.queue)
    }

    public var rawState: RawStateValue {
        state.rawValue
    }

    @discardableResult
    public func configureSensor(deviceNameOrSerial: String) -> Bool {
        let normalized = deviceNameOrSerial.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return false
        }

        let sensorSerial = Self.sensorSerial(from: normalized)
        let deviceName = normalized.contains("-") ? normalized : nil
        return configureSensor(deviceName: deviceName, sensorSerial: sensorSerial)
    }

    @discardableResult
    public func configureSensor(deviceName: String?, sensorSerial: String) -> Bool {
        let normalizedSerial = sensorSerial.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSerial.isEmpty else {
            return false
        }

        let normalizedDeviceName = deviceName?.trimmingCharacters(in: .whitespacesAndNewlines)
        var retiredSensor: MicroTechSensor?
        var cancelledRecoveryIdentifier: UUID?
        let stateChange = mutateProtectedState { protectedState in
            let isNewSensor = protectedState.state.sensorSerial != normalizedSerial
            let deviceNameChanged = protectedState.state.deviceName != normalizedDeviceName

            if isNewSensor || deviceNameChanged {
                protectedState.state.remoteIdentifier = nil
            }
            if isNewSensor {
                retiredSensor = protectedState.sensorIdentity.activeSensor
                switch protectedState.reconnectRecoveryState {
                case .idle:
                    break
                case .timing(let identifier), .shuttingDown(let identifier):
                    cancelledRecoveryIdentifier = identifier
                }
                protectedState.reconnectRecoveryState = .idle
                protectedState.state.activationTime = nil
                protectedState.state.lastReadingDate = nil
                protectedState.state.latestReading = nil
                protectedState.state.latestSampleNumber = nil
                protectedState.state.hasConnectedSensorSession = false
                protectedState.state.lastConnectionErrorDescription = nil
                protectedState.sensorIdentity.resetForSensorChange()
            }

            protectedState.state.deviceName = normalizedDeviceName
            protectedState.state.sensorSerial = normalizedSerial
        }
        retiredSensor?.retire()
        notifyStateDidChange(from: stateChange.oldState, to: stateChange.newState)
        if let cancelledRecoveryIdentifier {
            logDeviceCommunication(
                "MicroTech LinX reconnect recovery cancelled id=\(cancelledRecoveryIdentifier) reason=sensor changed",
                type: .connection
            )
        }
        return true
    }

    @discardableResult
    public func configureConnectionMode(_ mode: MicroTechCGMConnectionMode) -> Bool {
        var bluetoothManager: MicroTechBluetoothManaging?
        var managerToShutdown: MicroTechBluetoothManaging?
        var sensorToRetire: MicroTechSensor?
        let stateChange = mutateProtectedState { protectedState in
            let changedMode = protectedState.state.connectionMode != mode
            protectedState.state.connectionMode = mode
            if changedMode, mode != .direct {
                managerToShutdown = protectedState.bluetoothManager?.manager
                protectedState.bluetoothManager = nil
                protectedState.reconnectRecoveryState = .idle
            } else {
                bluetoothManager = protectedState.bluetoothManager?.manager
            }
            if mode == .broadcast {
                sensorToRetire = protectedState.sensorIdentity.activeSensor
                protectedState.sensorIdentity.retireActiveSensor()
                protectedState.sensorIdentity.activeSensor = nil
                protectedState.sensorIdentity.activeSensorConnectedAt = nil
                protectedState.sensorIdentity.staleConnectionWatchdogIdentifier = UUID()
            }
        }

        sensorToRetire?.retire()
        managerToShutdown?.shutdown {}
        bluetoothManager?.configureConnectionMode(mode)
        notifyStateDidChange(from: stateChange.oldState, to: stateChange.newState)
        return true
    }

    public var debugDescription: String {
        let state = self.state
        let lines = [
            "## MicroTechCGMManager",
            "remoteIdentifier: \(String(describing: state.remoteIdentifier))",
            "deviceName: \(String(describing: state.deviceName))",
            "sensorSerial: \(String(describing: state.sensorSerial))",
            "activationTime: \(String(describing: state.activationTime))",
            "lastReadingDate: \(String(describing: state.lastReadingDate))",
            "latestSampleNumber: \(String(describing: state.latestSampleNumber))",
            "hasConnectedSensorSession: \(state.hasConnectedSensorSession)",
            "uploadReadings: \(String(describing: state.uploadReadings))",
            "lastConnectionErrorDescription: \(String(describing: state.lastConnectionErrorDescription))",
        ]
        return lines.joined(separator: "\n")
    }

    public func fetchNewDataIfNeeded(_ completion: @escaping (CGMReadingResult) -> Void) {
        if state.connectionMode != .broadcast,
           disconnectStaleConnectedSensorIfNeeded()
        {
            completion(.noData)
            return
        }

        scanForSensor(clearingConnectionError: false)
        completion(.noData)
    }

    @discardableResult
    public func scanForSensor() -> Bool {
        scanForSensor(clearingConnectionError: true, expectedManager: nil, expectedSensor: nil)
    }

    @discardableResult
    private func scanForSensor(
        clearingConnectionError: Bool,
        expectedManager: MicroTechBluetoothManaging? = nil,
        expectedSensor: MicroTechSensor? = nil
    ) -> Bool {
        let candidateGeneration: MicroTechBluetoothManagerGeneration? = {
            let shouldCreateManager = readProtectedState { state in
                if let expectedManager,
                   !isCurrentBluetoothManager(expectedManager, in: state)
                {
                    return false
                }
                if let expectedSensor,
                   !isCurrentSensor(expectedSensor, in: state.sensorIdentity)
                {
                    return false
                }
                guard !state.sensorIdentity.isDeleted,
                      !state.reconnectRecoveryState.isShuttingDown
                else {
                    return false
                }
                return state.bluetoothManager == nil
            }
            guard shouldCreateManager else {
                return nil
            }
            return MicroTechBluetoothManagerGeneration(id: UUID(), manager: bluetoothManagerFactory())
        }()
        var generation: MicroTechBluetoothManagerGeneration?
        var scanDelegate: MicroTechBluetoothManagerDelegate?
        var connectionMode: MicroTechCGMConnectionMode = .direct
        var remoteIdentifier: UUID?
        var scanLogMessage: String?

        let stateChange = mutateProtectedState { protectedState in
            if let expectedManager,
               !isCurrentBluetoothManager(expectedManager, in: protectedState)
            {
                scanLogMessage = "MicroTech LinX scan ignored for retired Bluetooth manager"
                return
            }
            if let expectedSensor,
               !isCurrentSensor(expectedSensor, in: protectedState.sensorIdentity)
            {
                scanLogMessage = "MicroTech LinX scan ignored for retired sensor"
                return
            }
            guard !protectedState.sensorIdentity.isDeleted else {
                scanLogMessage = "MicroTech LinX scan ignored because CGM was deleted"
                return
            }
            guard case .shuttingDown = protectedState.reconnectRecoveryState else {
                if clearingConnectionError {
                    protectedState.state.lastConnectionErrorDescription = nil
                }

                connectionMode = protectedState.state.connectionMode
                remoteIdentifier = protectedState.state.remoteIdentifier
                guard let currentGeneration = protectedState.bluetoothManager ?? candidateGeneration else {
                    scanLogMessage = "MicroTech LinX scan ignored because Bluetooth manager is unavailable"
                    return
                }
                protectedState.bluetoothManager = currentGeneration
                generation = currentGeneration

                if connectionMode == .broadcast {
                    scanDelegate = self
                    scanLogMessage = "MicroTech LinX broadcast scan started"
                } else if let sensorSerial = protectedState.state.sensorSerial, !sensorSerial.isEmpty,
                          let activeSensor = protectedState.sensorIdentity.activeSensor
                {
                    scanDelegate = activeSensor
                    scanLogMessage = "MicroTech LinX scan using active sensor serial \(sensorSerial)"
                } else if let sensorSerial = protectedState.state.sensorSerial, !sensorSerial.isEmpty {
                    let session = MicroTechAidexSession(
                        remoteIdentifier: protectedState.state.remoteIdentifier ?? UUID(),
                        deviceName: protectedState.state.deviceName ?? "LinX-\(sensorSerial)",
                        sensorSerial: sensorSerial
                    )
                    let sensor = MicroTechSensor(
                        session: session,
                        peripheralSession: MicroTechPendingPeripheralSession(session: session)
                    )
                    sensor.delegate = self
                    scanDelegate = sensor
                    protectedState.sensorIdentity.activeSensor = sensor
                    scanLogMessage = "MicroTech LinX scan using saved sensor serial \(sensorSerial)"
                } else {
                    scanDelegate = self
                    scanLogMessage = "MicroTech LinX nearby scan started without saved sensor"
                }
                return
            }

            scanLogMessage = "MicroTech LinX scan ignored while Bluetooth manager is shutting down"
        }
        if let candidateGeneration,
           generation?.manager !== candidateGeneration.manager
        {
            candidateGeneration.manager.shutdown {}
        }
        notifyStateDidChange(from: stateChange.oldState, to: stateChange.newState)

        guard let generation, let scanDelegate else {
            if let scanLogMessage {
                logDeviceCommunication(scanLogMessage, type: .connection)
            }
            return false
        }

        startReconnectRecoveryIfNeeded(
            reason: clearingConnectionError ? "user scan" : "scan",
            expectedManager: expectedManager,
            expectedSensor: expectedSensor
        )
        guard isCurrentBluetoothManager(generation.manager, generationID: generation.id) else {
            return false
        }

        let bluetoothManager = generation.manager
        let logHandler: (String, MicroTechBluetoothLogType) -> Void = { [weak self] message, type in
            self?.logDeviceCommunication(message, type: type.deviceLogEntryType)
        }
        let wasConnected = bluetoothManager.isConnected
        let wasScanning = bluetoothManager.isScanning
        switch connectionMode {
        case .direct:
            bluetoothManager.activateDirectScan(
                delegate: scanDelegate,
                logHandler: logHandler,
                remoteIdentifier: remoteIdentifier
            )
        case .broadcast:
            bluetoothManager.activateBroadcastScan(
                delegate: scanDelegate,
                logHandler: logHandler,
                remoteIdentifier: remoteIdentifier
            )
        }

        guard isCurrentBluetoothManager(bluetoothManager, generationID: generation.id) else {
            return false
        }
        if !(wasScanning || wasConnected) {
            if let scanLogMessage {
                logDeviceCommunication("\(scanLogMessage), remoteIdentifier \(String(describing: remoteIdentifier))", type: .connection)
            }
        } else if wasConnected {
            bluetoothManager.refreshConnectedPeripheral()
            logDeviceCommunication("MicroTech LinX refreshing connected Bluetooth session", type: .connection)
        } else {
            logDeviceCommunication("MicroTech LinX scan skipped because Bluetooth is already scanning or connected", type: .connection)
        }
        return true
    }

    public func delete(completion: @escaping () -> Void) {
        var sensorToStop: MicroTechSensor?
        var bluetoothManagerToDisconnect: MicroTechBluetoothManaging?
        let stateChange = mutateProtectedState { protectedState in
            sensorToStop = protectedState.sensorIdentity.activeSensor
            bluetoothManagerToDisconnect = protectedState.bluetoothManager?.manager
            protectedState.sensorIdentity.retireActiveSensor()
            protectedState.sensorIdentity.activeSensor = nil
            protectedState.sensorIdentity.isDeleted = true
            protectedState.bluetoothManager = nil
            protectedState.reconnectRecoveryState = .idle

            protectedState.state.remoteIdentifier = nil
            protectedState.state.deviceName = nil
            protectedState.state.sensorSerial = nil
            protectedState.state.activationTime = nil
            protectedState.state.lastReadingDate = nil
            protectedState.state.latestReading = nil
            protectedState.state.latestSampleNumber = nil
            protectedState.state.hasConnectedSensorSession = false
            protectedState.state.lastConnectionErrorDescription = nil
        }
        notifyStateDidChange(from: stateChange.oldState, to: stateChange.newState)
        bluetoothManagerToDisconnect?.shutdown {}
        sensorToStop?.retire()
        notifyDelegateOfDeletion(completion: completion)
    }

    public func addStatusObserver(_ observer: CGMManagerStatusObserver, queue: DispatchQueue) {
        statusObservers.insert(observer, queue: queue)
    }

    public func removeStatusObserver(_ observer: CGMManagerStatusObserver) {
        statusObservers.removeElement(observer)
    }

    public func acknowledgeAlert(alertIdentifier: Alert.AlertIdentifier, completion: @escaping (Error?) -> Void) {
        completion(nil)
    }

    public func getSoundBaseURL() -> URL? {
        nil
    }

    public func getSounds() -> [Alert.Sound] {
        []
    }

    func accept(_ reading: MicroTechGlucoseReading) -> NewGlucoseSample? {
        guard reading.isValidForTherapy else {
            return nil
        }

        var sample: NewGlucoseSample?
        mutateState { state in
            if state.sensorSerial == reading.sensorSerial,
               let latestSampleNumber = state.latestSampleNumber,
               Self.isSampleNumber(reading.sampleNumber, notNewerThan: latestSampleNumber)
            {
                return
            }

            state.sensorSerial = reading.sensorSerial
            state.lastReadingDate = reading.receivedAt
            state.latestReading = reading
            state.latestSampleNumber = reading.sampleNumber
            state.hasConnectedSensorSession = true
            state.lastConnectionErrorDescription = nil
            sample = makeSample(from: reading, state: state)
        }

        return sample
    }

    @discardableResult
    func acceptBroadcastAdvertisement(_ advertisement: MicroTechBroadcastAdvertisement) throws -> NewGlucoseSample? {
        let broadcastReading = try MicroTechAidexBroadcastParser.parseAdvertisementData(advertisement.advertisementData)
        logBroadcastParsed(broadcastReading, advertisement: advertisement)
        return acceptBroadcastReading(broadcastReading, advertisement: advertisement, expectedManager: nil).sample
    }

    private func logBroadcastParsed(
        _ broadcastReading: MicroTechAidexBroadcastReading,
        advertisement: MicroTechBroadcastAdvertisement
    ) {
        let sensorSerial = Self.broadcastSensorSerial(from: advertisement, currentState: state)
        logDeviceCommunication(
            "MicroTech LinX stage=broadcast event=parsed \(Self.broadcastAdvertisementContext(advertisement)) \(Self.broadcastReadingContext(broadcastReading, sensorSerial: sensorSerial))",
            type: .receive
        )
    }

    func logBroadcastParseError(_ error: Error, advertisement: MicroTechBroadcastAdvertisement) {
        let advertisementDescription = MicroTechBluetoothManager.advertisementDescription(advertisement.advertisementData)
        logDeviceCommunication(
            "MicroTech LinX stage=broadcast event=rejected reason=parseError \(Self.broadcastAdvertisementContext(advertisement)) error=\(String(describing: error)) advertisement=\(advertisementDescription)",
            type: .receive
        )
    }

    @discardableResult
    private func acceptBroadcastReading(
        _ broadcastReading: MicroTechAidexBroadcastReading,
        advertisement: MicroTechBroadcastAdvertisement,
        expectedManager: MicroTechBluetoothManaging?
    ) -> (sourceAccepted: Bool, sample: NewGlucoseSample?) {
        var sourceAccepted = true
        var sample: NewGlucoseSample?
        var logMessage: String?
        let filterStartDate = startDateToFilterNewData()

        let stateChange = mutateProtectedState { state in
            if let expectedManager,
               !isCurrentBluetoothManager(expectedManager, in: state)
            {
                sourceAccepted = false
                return
            }
            guard !state.sensorIdentity.isDeleted else {
                logMessage = "stage=broadcast event=rejected reason=deleted"
                return
            }
            guard state.state.connectionMode == .broadcast else {
                logMessage = "stage=broadcast event=rejected reason=notBroadcastMode"
                return
            }
            guard let latestRecord = broadcastReading.latestRecord else {
                logMessage = "stage=broadcast event=rejected reason=noRecords"
                return
            }

            let glucoseMgdl = latestRecord.glucose
            guard (40...400).contains(glucoseMgdl) else {
                logMessage = "stage=broadcast event=rejected reason=invalidGlucose value=\(glucoseMgdl)"
                return
            }

            guard let sensorSerial = Self.broadcastSensorSerial(from: advertisement, currentState: state.state) else {
                logMessage = "stage=broadcast event=rejected reason=missingSerial"
                return
            }

            if let existingSerial = state.state.sensorSerial,
               !existingSerial.isEmpty,
               existingSerial != sensorSerial
            {
                logMessage = "stage=broadcast event=rejected reason=serialMismatch serial=\(sensorSerial) saved=\(existingSerial)"
                return
            }

            if let filterStartDate, advertisement.discoveredAt < filterStartDate {
                logMessage = "stage=broadcast event=rejected reason=beforeStartDate at=\(advertisement.discoveredAt) startDate=\(filterStartDate)"
                return
            }

            let sampleNumber = Int(latestRecord.timeOffset)
            if state.state.sensorSerial == sensorSerial,
               let latestSampleNumber = state.state.latestSampleNumber,
               Self.isSampleNumber(sampleNumber, notNewerThan: latestSampleNumber)
            {
                logMessage = "stage=broadcast event=rejected reason=duplicateOrOld serial=\(sensorSerial) sample=\(sampleNumber) latest=\(latestSampleNumber)"
                return
            }

            let deviceName = advertisement.deviceName ?? state.state.deviceName ?? "LinX-\(sensorSerial)"
            let reading = MicroTechGlucoseReading(
                sensorSerial: sensorSerial,
                sampleNumber: sampleNumber,
                glucoseMgdl: glucoseMgdl,
                trend: broadcastReading.trend,
                receivedAt: advertisement.discoveredAt,
                status: Int(broadcastReading.status),
                quality: Int(latestRecord.quality),
                rawBytes: broadcastReading.rawManufacturerPayload
            )

            state.sensorIdentity.activeSensor = nil
            state.sensorIdentity.activeSensorConnectedAt = nil
            state.sensorIdentity.consecutiveSensorErrorCount = 0
            state.sensorIdentity.savedIdentifierFailureCount = 0
            state.sensorIdentity.pendingReconnectRecoveryReason = nil
            state.sensorIdentity.resetHistoryTracking()
            state.state.connectionMode = .broadcast
            state.state.remoteIdentifier = advertisement.identifier
            state.state.deviceName = deviceName
            state.state.sensorSerial = sensorSerial
            state.state.lastReadingDate = advertisement.discoveredAt
            state.state.latestReading = reading
            state.state.latestSampleNumber = sampleNumber
            state.state.hasConnectedSensorSession = true
            state.state.lastConnectionErrorDescription = nil
            sample = makeSample(
                sensorSerial: sensorSerial,
                sampleNumber: sampleNumber,
                glucoseMgdl: glucoseMgdl,
                date: advertisement.discoveredAt,
                state: state.state
            )
            logMessage = "stage=broadcast event=accepted \(Self.broadcastAdvertisementContext(advertisement)) \(Self.broadcastReadingContext(broadcastReading, sensorSerial: sensorSerial))"
        }

        guard sourceAccepted else {
            return (false, nil)
        }
        notifyStateDidChange(from: stateChange.oldState, to: stateChange.newState)
        if let logMessage {
            logDeviceCommunication("MicroTech LinX \(logMessage)", type: sample == nil ? .connection : .receive)
        }
        return (true, sample)
    }

    private static func broadcastAdvertisementContext(_ advertisement: MicroTechBroadcastAdvertisement) -> String {
        "identifier=\(advertisement.identifier) name=\(advertisement.deviceName ?? "nil") localName=\(advertisement.localName ?? "nil") peripheralName=\(advertisement.peripheralName ?? "nil") rssi=\(advertisement.rssi)"
    }

    private static func broadcastReadingContext(
        _ broadcastReading: MicroTechAidexBroadcastReading,
        sensorSerial: String?
    ) -> String {
        guard let latestRecord = broadcastReading.latestRecord else {
            return "serial=\(sensorSerial ?? "nil") sample=nil value=nil quality=nil trend=\(broadcastReading.trend) status=\(broadcastReading.status) records=\(broadcastReading.records.count) rawHex=\(broadcastReading.rawManufacturerPayload.microTechHexadecimalString)"
        }
        return "serial=\(sensorSerial ?? "nil") sample=\(latestRecord.timeOffset) value=\(latestRecord.glucose) quality=\(latestRecord.quality) trend=\(broadcastReading.trend) status=\(broadcastReading.status) records=\(broadcastReading.records.count) rawHex=\(broadcastReading.rawManufacturerPayload.microTechHexadecimalString)"
    }

    func makeSample(from reading: MicroTechGlucoseReading) -> NewGlucoseSample {
        makeSample(from: reading, state: state)
    }

    private func makeSample(from reading: MicroTechGlucoseReading, state: MicroTechCGMManagerState) -> NewGlucoseSample {
        NewGlucoseSample(
            date: reading.receivedAt,
            quantity: reading.glucoseQuantity!,
            condition: nil,
            trend: reading.trendType,
            trendRate: reading.trendRate,
            isDisplayOnly: false,
            wasUserEntered: false,
            syncIdentifier: reading.syncIdentifier,
            device: device(for: state)
        )
    }

    private func makeSample(
        sensorSerial: String,
        sampleNumber: Int,
        glucoseMgdl: Int,
        date: Date,
        state: MicroTechCGMManagerState
    ) -> NewGlucoseSample {
        NewGlucoseSample(
            date: date,
            quantity: HKQuantity(unit: Self.glucoseUnit, doubleValue: Double(glucoseMgdl)),
            condition: nil,
            trend: nil,
            trendRate: nil,
            isDisplayOnly: false,
            wasUserEntered: false,
            syncIdentifier: "\(sensorSerial)-\(sampleNumber)",
            device: device(for: state)
        )
    }

    @discardableResult
    private func mutateState(_ mutation: (inout MicroTechCGMManagerState) -> Void) -> MicroTechCGMManagerState {
        let stateChange = mutateProtectedState { protectedState in
            mutation(&protectedState.state)
        }

        notifyStateDidChange(from: stateChange.oldState, to: stateChange.newState)
        return stateChange.newState
    }

    private func notifyDelegateOfReadingResult(_ result: CGMReadingResult) {
        delegate.notify { delegate in
            delegate?.cgmManager(self, hasNew: result)
        }
    }

    func recordBluetoothFailure(
        _ error: Error,
        expectedManager: MicroTechBluetoothManaging? = nil,
        expectedSensor: MicroTechSensor? = nil
    ) {
        var didAcceptSource = true
        var shouldRetrySavedSensorScan = false
        var shouldRestartForNearbySerialScan = false
        var bluetoothManagerToRestart: MicroTechBluetoothManaging?
        var fallbackFailureCount = 0
        var recoveryIdentifier: UUID?
        let stateChange = mutateProtectedState { state in
            if let expectedManager,
               !isCurrentBluetoothManager(expectedManager, in: state)
            {
                didAcceptSource = false
                return
            }
            if let expectedSensor,
               !isCurrentSensor(expectedSensor, in: state.sensorIdentity)
            {
                didAcceptSource = false
                return
            }

            state.state.lastConnectionErrorDescription = "Bluetooth failed: \(String(describing: error))"
            state.sensorIdentity.activeSensorConnectedAt = nil
            state.sensorIdentity.staleConnectionWatchdogIdentifier = UUID()
            recoveryIdentifier = claimReconnectRecoveryIfNeeded(reason: "Bluetooth failure", in: &state)
            guard let bluetoothError = error as? MicroTechBluetoothManagerError,
                  state.state.sensorSerial?.isEmpty == false,
                  !state.sensorIdentity.isDeleted
            else {
                return
            }

            if let failedIdentifier = Self.failedRemoteIdentifier(from: bluetoothError),
               let savedIdentifier = state.state.remoteIdentifier,
               failedIdentifier == savedIdentifier
            {
                state.sensorIdentity.savedIdentifierFailureCount += 1
                fallbackFailureCount = state.sensorIdentity.savedIdentifierFailureCount
                if state.sensorIdentity.savedIdentifierFailureCount >= Self.savedIdentifierFallbackFailureThreshold {
                    state.sensorIdentity.savedIdentifierFailureCount = 0
                    state.state.remoteIdentifier = nil
                    bluetoothManagerToRestart = state.bluetoothManager?.manager
                    shouldRestartForNearbySerialScan = true
                    return
                }
            }

            if case .scanTimeout = bluetoothError {
                shouldRetrySavedSensorScan = true
            }
        }
        guard didAcceptSource else {
            return
        }
        notifyStateDidChange(from: stateChange.oldState, to: stateChange.newState)
        if let recoveryIdentifier {
            scheduleReconnectRecovery(identifier: recoveryIdentifier, reason: "Bluetooth failure")
        }
        logDeviceCommunication("MicroTech LinX Bluetooth failed: \(String(describing: error))", type: .error)
        if shouldRestartForNearbySerialScan {
            logDeviceCommunication("MicroTech LinX clearing saved Bluetooth identifier after \(fallbackFailureCount) failures and scanning by sensor serial", type: .connection)
            bluetoothManagerToRestart?.disconnect()
            bluetoothRetryScheduler { [weak self] in
                self?.scanForSensor(
                    clearingConnectionError: false,
                    expectedManager: expectedManager,
                    expectedSensor: expectedSensor
                )
            }
        } else if shouldRetrySavedSensorScan {
            logDeviceCommunication("MicroTech LinX retrying saved sensor scan after Bluetooth scan timeout", type: .connection)
            bluetoothRetryScheduler { [weak self] in
                self?.scanForSensor(
                    clearingConnectionError: false,
                    expectedManager: expectedManager,
                    expectedSensor: expectedSensor
                )
            }
        }
        notifyDelegateOfReadingResult(.error(error))
    }

    func shouldConnectToMicroTechDevice(deviceName: String, identifier: UUID) -> Bool {
        shouldConnectToMicroTechDevice(deviceName: deviceName, identifier: identifier, currentState: state)
    }

    private func shouldConnectToMicroTechDevice(
        deviceName: String,
        identifier: UUID,
        currentState: MicroTechCGMManagerState
    ) -> Bool {
        if currentState.remoteIdentifier == identifier {
            logDeviceCommunication("MicroTech LinX scan accepted saved identifier \(identifier)", type: .connection)
            return true
        }

        guard let advertisedSerial = Self.advertisedSensorSerial(from: deviceName) else {
            logDeviceCommunication("MicroTech LinX scan rejected advertised device \(deviceName), identifier \(identifier)", type: .connection)
            return false
        }

        if let sensorSerial = currentState.sensorSerial, !sensorSerial.isEmpty {
            let matchesSavedSerial = advertisedSerial == sensorSerial
            logDeviceCommunication(
                "MicroTech LinX scan \(matchesSavedSerial ? "accepted" : "rejected") advertised device \(deviceName), identifier \(identifier)",
                type: .connection
            )
            return matchesSavedSerial
        }

        logDeviceCommunication("MicroTech LinX scan accepted advertised device \(deviceName), identifier \(identifier)", type: .connection)
        return true
    }

    static func isReconnectRecoveryEligible(
        hasConnectedSensorSession: Bool,
        sensorSerial: String?,
        connectionMode: MicroTechCGMConnectionMode,
        isDeleted: Bool,
        hasCurrentHandshake: Bool
    ) -> Bool {
        !isDeleted &&
            connectionMode == .direct &&
            hasConnectedSensorSession &&
            sensorSerial?.isEmpty == false &&
            !hasCurrentHandshake
    }

    private func isReconnectRecoveryEligible(_ state: MicroTechCGMManagerProtectedState) -> Bool {
        Self.isReconnectRecoveryEligible(
            hasConnectedSensorSession: state.state.hasConnectedSensorSession,
            sensorSerial: state.state.sensorSerial,
            connectionMode: state.state.connectionMode,
            isDeleted: state.sensorIdentity.isDeleted,
            hasCurrentHandshake: state.sensorIdentity.activeSensorConnectedAt != nil
        )
    }

    private func startReconnectRecoveryIfNeeded(
        reason: String,
        expectedManager: MicroTechBluetoothManaging? = nil,
        expectedSensor: MicroTechSensor? = nil
    ) {
        var identifier: UUID?
        _ = mutateProtectedState { state in
            if let expectedManager,
               !isCurrentBluetoothManager(expectedManager, in: state)
            {
                return
            }
            if let expectedSensor,
               !isCurrentSensor(expectedSensor, in: state.sensorIdentity)
            {
                return
            }
            identifier = claimReconnectRecoveryIfNeeded(reason: reason, in: &state)
        }

        guard let identifier else {
            return
        }
        scheduleReconnectRecovery(identifier: identifier, reason: reason)
    }

    private func claimReconnectRecoveryIfNeeded(
        reason: String,
        in state: inout MicroTechCGMManagerProtectedState
    ) -> UUID? {
        guard isReconnectRecoveryEligible(state),
              case .idle = state.reconnectRecoveryState
        else {
            return nil
        }

        let identifier = UUID()
        state.reconnectRecoveryState = .timing(id: identifier)
        if state.sensorIdentity.pendingReconnectRecoveryReason == nil {
            state.sensorIdentity.pendingReconnectRecoveryReason = reason
        }
        return identifier
    }

    private func scheduleReconnectRecovery(identifier: UUID, reason: String) {
        logDeviceCommunication(
            "MicroTech LinX reconnect recovery started id=\(identifier) reason=\(reason) timeout=60",
            type: .connection
        )
        reconnectRecoveryScheduler(Self.reconnectRecoveryInterval) { [weak self] in
            self?.runReconnectRecoveryTimeout(identifier: identifier)
        }
    }

    private func cancelReconnectRecovery(reason: String) {
        var cancelledIdentifier: UUID?
        _ = mutateProtectedState { state in
            switch state.reconnectRecoveryState {
            case .idle:
                return
            case .timing(let identifier), .shuttingDown(let identifier):
                cancelledIdentifier = identifier
                state.reconnectRecoveryState = .idle
            }
        }
        if let cancelledIdentifier {
            logDeviceCommunication(
                "MicroTech LinX reconnect recovery cancelled id=\(cancelledIdentifier) reason=\(reason)",
                type: .connection
            )
        }
    }

    private func runReconnectRecoveryTimeout(identifier: UUID) {
        var generation: MicroTechBluetoothManagerGeneration?
        var sensorToStop: MicroTechSensor?
        let stateChange = mutateProtectedState { state in
            guard case .timing(let currentIdentifier) = state.reconnectRecoveryState,
                  currentIdentifier == identifier,
                  isReconnectRecoveryEligible(state),
                  let currentGeneration = state.bluetoothManager
            else {
                return
            }

            state.reconnectRecoveryState = .shuttingDown(id: identifier)
            generation = currentGeneration
            state.bluetoothManager = nil
            state.state.remoteIdentifier = nil
            sensorToStop = retireActiveSensor(in: &state.sensorIdentity)
            state.sensorIdentity.clearPendingHistoryRequest()
        }
        notifyStateDidChange(from: stateChange.oldState, to: stateChange.newState)

        guard let generation else {
            return
        }
        logDeviceCommunication(
            "MicroTech LinX reconnect recovery timeout id=\(identifier) after=60 action=rebuild",
            type: .connection
        )
        sensorToStop?.retire()
        generation.manager.shutdown { [weak self] in
            self?.completeBluetoothManagerShutdown(recoveryIdentifier: identifier)
        }
    }

    private func completeBluetoothManagerShutdown(recoveryIdentifier: UUID) {
        var shouldCreateReplacement = false
        _ = mutateProtectedState { state in
            guard case .shuttingDown(let currentIdentifier) = state.reconnectRecoveryState,
                  currentIdentifier == recoveryIdentifier
            else {
                return
            }
            guard isReconnectRecoveryEligible(state) else {
                state.reconnectRecoveryState = .idle
                return
            }
            shouldCreateReplacement = true
        }
        guard shouldCreateReplacement else {
            return
        }

        let candidateManager = bluetoothManagerFactory()
        var replacement: MicroTechBluetoothManagerGeneration?
        var replacementRecoveryIdentifier: UUID?
        let stateChange = mutateProtectedState { state in
            guard case .shuttingDown(let currentIdentifier) = state.reconnectRecoveryState,
                  currentIdentifier == recoveryIdentifier,
                  isReconnectRecoveryEligible(state)
            else {
                if case .shuttingDown(let currentIdentifier) = state.reconnectRecoveryState,
                   currentIdentifier == recoveryIdentifier
                {
                    state.reconnectRecoveryState = .idle
                }
                return
            }

            let generation = MicroTechBluetoothManagerGeneration(id: UUID(), manager: candidateManager)
            let nextRecoveryIdentifier = UUID()
            guard let sensor = makePendingSensor(for: state.state) else {
                state.reconnectRecoveryState = .idle
                return
            }
            state.bluetoothManager = generation
            state.reconnectRecoveryState = .timing(id: nextRecoveryIdentifier)
            state.sensorIdentity.restore(sensor)
            state.sensorIdentity.activeSensor = sensor
            replacement = generation
            replacementRecoveryIdentifier = nextRecoveryIdentifier
        }
        notifyStateDidChange(from: stateChange.oldState, to: stateChange.newState)

        guard let replacement, let replacementRecoveryIdentifier else {
            candidateManager.shutdown {}
            return
        }
        logDeviceCommunication(
            "MicroTech LinX Bluetooth shutdown completed id=\(recoveryIdentifier); rebuilding scan by serial",
            type: .connection
        )
        reconnectRecoveryScheduler(Self.reconnectRecoveryInterval) { [weak self] in
            self?.runReconnectRecoveryTimeout(identifier: replacementRecoveryIdentifier)
        }
        activateReplacementManager(
            replacement.manager,
            generationID: replacement.id,
            recoveryIdentifier: replacementRecoveryIdentifier
        )
    }

    private func activateReplacementManager(
        _ manager: MicroTechBluetoothManaging,
        generationID: UUID,
        recoveryIdentifier: UUID
    ) {
        let delegate = readProtectedState { state -> MicroTechBluetoothManagerDelegate? in
            guard state.bluetoothManager?.id == generationID,
                  state.bluetoothManager?.manager === manager,
                  case .timing(let currentIdentifier) = state.reconnectRecoveryState,
                  currentIdentifier == recoveryIdentifier,
                  state.state.connectionMode == .direct,
                  !state.sensorIdentity.isDeleted
            else {
                return nil
            }
            return state.sensorIdentity.activeSensor
        }
        guard let delegate else {
            manager.shutdown {}
            return
        }
        manager.activateDirectScan(
            delegate: delegate,
            logHandler: { [weak self] message, type in
                self?.logDeviceCommunication(message, type: type.deviceLogEntryType)
            },
            remoteIdentifier: nil
        )
    }

    private func makePendingSensor(for state: MicroTechCGMManagerState) -> MicroTechSensor? {
        guard let sensorSerial = state.sensorSerial, !sensorSerial.isEmpty else {
            return nil
        }
        let session = MicroTechAidexSession(
            remoteIdentifier: UUID(),
            deviceName: state.deviceName ?? "LinX-\(sensorSerial)",
            sensorSerial: sensorSerial
        )
        let sensor = MicroTechSensor(
            session: session,
            peripheralSession: MicroTechPendingPeripheralSession(session: session)
        )
        sensor.delegate = self
        return sensor
    }

    private func retireActiveSensor(in state: inout MicroTechSensorIdentityState) -> MicroTechSensor? {
        let sensor = state.activeSensor
        state.retireActiveSensor()
        state.activeSensor = nil
        state.activeSensorConnectedAt = nil
        state.staleConnectionWatchdogIdentifier = UUID()
        return sensor
    }

    private func isCurrentBluetoothManager(
        _ manager: MicroTechBluetoothManaging,
        generationID: UUID? = nil
    ) -> Bool {
        readProtectedState { state in
            isCurrentBluetoothManager(manager, generationID: generationID, in: state)
        }
    }

    private func isCurrentBluetoothManager(
        _ manager: MicroTechBluetoothManaging,
        generationID: UUID? = nil,
        in state: MicroTechCGMManagerProtectedState
    ) -> Bool {
        guard let current = state.bluetoothManager,
              current.manager === manager,
              !state.sensorIdentity.isDeleted
        else {
            return false
        }
        return generationID == nil || generationID == current.id
    }

    var reconnectRecoveryPhaseForTesting: String {
        readProtectedState { state in
            switch state.reconnectRecoveryState {
            case .idle: return "idle"
            case .timing: return "timing"
            case .shuttingDown: return "shuttingDown"
            }
        }
    }

    var emittedHistorySamplesForTesting: Set<Int> {
        readProtectedState { $0.sensorIdentity.emittedHistorySampleNumbers }
    }

    var pendingHistoryRequestForTesting: Int? {
        readProtectedState { $0.sensorIdentity.historyBackfillRequestedFrom }
    }

    func registerSensorForTesting(_ sensor: MicroTechSensor) {
        var sensorToRetire: MicroTechSensor?
        _ = mutateProtectedState { state in
            guard !state.sensorIdentity.isDeleted,
                  state.sensorIdentity.activeSensor !== sensor
            else {
                return
            }
            sensorToRetire = state.sensorIdentity.activeSensor
            state.sensorIdentity.retireActiveSensor()
            state.sensorIdentity.restore(sensor)
            state.sensorIdentity.activeSensor = sensor
        }
        sensorToRetire?.retire()
    }

    private func isCurrentSensor(_ sensor: MicroTechSensor, in state: MicroTechSensorIdentityState) -> Bool {
        !state.isDeleted && state.activeSensor === sensor && !state.isRetired(sensor)
    }

    private func acceptSensorConnection(
        _ sensor: MicroTechSensor,
        session: MicroTechAidexSession,
        in state: inout MicroTechCGMManagerProtectedState
    ) -> Bool {
        guard !state.sensorIdentity.isDeleted,
              state.sensorIdentity.activeSensor === sensor,
              !state.sensorIdentity.isRetired(sensor)
        else {
            return false
        }

        if let sensorSerial = state.state.sensorSerial, sensorSerial != session.sensorSerial {
            state.state.activationTime = nil
            state.state.lastReadingDate = nil
            state.state.latestReading = nil
            state.state.latestSampleNumber = nil
            state.state.hasConnectedSensorSession = false
            state.state.lastConnectionErrorDescription = nil
            state.sensorIdentity.resetHistoryTracking()
        }

        state.sensorIdentity.activeSensor = sensor
        state.sensorIdentity.activeSensorConnectedAt = dateProvider()
        state.sensorIdentity.staleConnectionWatchdogIdentifier = UUID()
        state.sensorIdentity.consecutiveSensorErrorCount = 0
        state.sensorIdentity.savedIdentifierFailureCount = 0
        state.state.remoteIdentifier = session.remoteIdentifier
        state.state.deviceName = session.deviceName
        state.state.sensorSerial = session.sensorSerial
        state.state.hasConnectedSensorSession = true
        state.state.lastConnectionErrorDescription = nil
        return true
    }

    private func mutateProtectedState(
        _ mutation: (inout MicroTechCGMManagerProtectedState) -> Void
    ) -> (oldState: MicroTechCGMManagerState, newState: MicroTechCGMManagerState) {
        var oldState: MicroTechCGMManagerState!
        let protectedState = lockedManagerState.mutate { state in
            oldState = state.state
            mutation(&state)
        }
        return (oldState, protectedState.state)
    }

    private func readProtectedState<Value>(_ read: (MicroTechCGMManagerProtectedState) -> Value) -> Value {
        var value: Value!
        lockedManagerState.mutate { state in
            value = read(state)
        }
        return value
    }

    private func notifyStateDidChange(from oldValue: MicroTechCGMManagerState, to newValue: MicroTechCGMManagerState) {
        guard oldValue != newValue else {
            return
        }

        let status = cgmManagerStatus
        delegate.notify { delegate in
            delegate?.cgmManagerDidUpdateState(self)
            delegate?.cgmManager(self, didUpdate: status)
        }
        statusObservers.forEach { observer in
            observer.cgmManager(self, didUpdate: status)
        }
    }

    private func logDeviceCommunication(_ message: String, type: DeviceLogEntryType = .send) {
        os_log("%{public}@", log: log, type: .default, message)
        let deviceIdentifier = state.sensorSerial
        switch deviceLogDestination.value {
        case .onboarding(let handler):
            handler(deviceIdentifier, type, message)
        case .formalDelegate:
            delegate.notify { delegate in
                delegate?.deviceManager(self, logEventForDeviceIdentifier: deviceIdentifier, type: type, message: message, completion: nil)
            }
        case .systemOnly:
            break
        }
    }

    private func resumeSavedSensorScanIfNeeded(
        reason: String,
        expectedManager: MicroTechBluetoothManaging? = nil,
        expectedSensor: MicroTechSensor? = nil
    ) {
        let resumeContext = readProtectedState { state -> (accepted: Bool, generation: MicroTechBluetoothManagerGeneration?) in
            if let expectedManager,
               !isCurrentBluetoothManager(expectedManager, in: state)
            {
                return (false, nil)
            }
            if let expectedSensor,
               !isCurrentSensor(expectedSensor, in: state.sensorIdentity)
            {
                return (false, nil)
            }
            guard !state.sensorIdentity.isDeleted,
                  state.state.sensorSerial?.isEmpty == false,
                  !state.reconnectRecoveryState.isShuttingDown
            else {
                return (false, nil)
            }
            return (true, state.bluetoothManager)
        }

        guard resumeContext.accepted else {
            return
        }
        let generation = resumeContext.generation

        if let generation,
           (generation.manager.isScanning || generation.manager.isConnected)
        {
            return
        }

        startReconnectRecoveryIfNeeded(
            reason: reason,
            expectedManager: expectedManager,
            expectedSensor: expectedSensor
        )
        logDeviceCommunication("MicroTech LinX resume scan after \(reason)", type: .connection)
        scanForSensor(
            clearingConnectionError: false,
            expectedManager: expectedManager,
            expectedSensor: expectedSensor
        )
    }

    private func scheduleResumeSavedSensorScanIfNeeded(
        reason: String,
        expectedManager: MicroTechBluetoothManaging? = nil,
        expectedSensor: MicroTechSensor? = nil
    ) {
        bluetoothRetryScheduler { [weak self] in
            self?.resumeSavedSensorScanIfNeeded(
                reason: reason,
                expectedManager: expectedManager,
                expectedSensor: expectedSensor
            )
        }
    }

    private func resumeSavedSensorScanAfterDelegateQueueConfiguredIfNeeded() {
        guard resumeScanWhenDelegateQueueConfigured,
              !didResumeScanWhenDelegateQueueConfigured else
        {
            return
        }

        didResumeScanWhenDelegateQueueConfigured = true
        resumeSavedSensorScanIfNeeded(reason: "delegate queue configured")
    }

    private func scheduleStaleConnectionWatchdogIfNeeded(reason: String) {
        let watchdogIdentifier = UUID()
        var shouldSchedule = false
        lockedManagerState.mutate { state in
            guard !state.sensorIdentity.isDeleted,
                  state.state.sensorSerial?.isEmpty == false,
                  state.sensorIdentity.activeSensorConnectedAt != nil
            else {
                return
            }

            state.sensorIdentity.staleConnectionWatchdogIdentifier = watchdogIdentifier
            shouldSchedule = true
        }

        guard shouldSchedule else {
            return
        }

        staleConnectionScheduler(Self.staleReadingReconnectInterval) { [weak self] in
            self?.runStaleConnectionWatchdog(identifier: watchdogIdentifier, reason: reason)
        }
    }

    private func runStaleConnectionWatchdog(identifier: UUID, reason: String) {
        let shouldRun = readProtectedState { state in
            !state.sensorIdentity.isDeleted &&
                state.sensorIdentity.staleConnectionWatchdogIdentifier == identifier
        }

        guard shouldRun else {
            return
        }

        if disconnectStaleConnectedSensorIfNeeded() {
            return
        }

        scheduleStaleConnectionWatchdogIfNeeded(reason: "\(reason) refresh")
    }

    private func invalidateStaleConnectionWatchdog() {
        lockedManagerState.mutate { state in
            state.sensorIdentity.staleConnectionWatchdogIdentifier = UUID()
        }
    }

    private func clearConnectedSensorWatchdogState(recoveryReason: String? = nil) {
        lockedManagerState.mutate { state in
            state.sensorIdentity.activeSensorConnectedAt = nil
            state.sensorIdentity.staleConnectionWatchdogIdentifier = UUID()
            if let recoveryReason {
                state.sensorIdentity.pendingReconnectRecoveryReason = recoveryReason
            }
        }
    }

    private func disconnectStaleConnectedSensorIfNeeded() -> Bool {
        let generation = readProtectedState { $0.bluetoothManager }
        guard let generation, generation.manager.isConnected else {
            return false
        }

        var bluetoothManager: MicroTechBluetoothManaging?
        var disconnectReason = "stale reading"
        let now = dateProvider()
        let shouldDisconnect = readProtectedState { state in
            guard state.state.sensorSerial?.isEmpty == false,
                  state.bluetoothManager?.id == generation.id else
            {
                return false
            }

            let referenceDate: Date
            if let lastReadingDate = state.state.lastReadingDate {
                referenceDate = lastReadingDate
            } else if let connectedAt = state.sensorIdentity.activeSensorConnectedAt {
                referenceDate = connectedAt
                disconnectReason = "no readings after connect"
            } else {
                return false
            }

            guard now.timeIntervalSince(referenceDate) >= Self.staleReadingReconnectInterval else {
                return false
            }

            bluetoothManager = generation.manager
            return true
        }

        guard shouldDisconnect, let bluetoothManager else {
            return false
        }

        logDeviceCommunication("MicroTech LinX disconnecting stale connection to restart Bluetooth scan reason=\(disconnectReason)", type: .connection)
        clearConnectedSensorWatchdogState(recoveryReason: disconnectReason)
        bluetoothManager.disconnect()
        scanForSensor(clearingConnectionError: false)
        return true
    }

    private func scheduleHistoryBackfillIfNeeded(
        currentIndex: Int,
        in sensorIdentity: inout MicroTechSensorIdentityState
    ) -> MicroTechHistoryRequest? {
        guard let fromIndex = Self.nextHistoryRequestIndex(
            currentIndex: currentIndex,
            historySamples: sensorIdentity.emittedHistorySampleNumbers
        ) else {
            sensorIdentity.clearPendingHistoryRequest()
            return nil
        }

        return scheduleHistoryRequest(
            fromIndex: fromIndex,
            currentIndex: currentIndex,
            reason: .backfill,
            in: &sensorIdentity
        )
    }

    private func scheduleNextHistoryRequestIfNeeded(
        history: MicroTechAidexHistoryPacket,
        latestCurrentIndex: Int?,
        in sensorIdentity: inout MicroTechSensorIdentityState
    ) -> MicroTechHistoryRequest? {
        guard let latestCurrentIndex,
              let lastRecord = history.records.last else
        {
            return nil
        }

        if let requestedFrom = sensorIdentity.historyBackfillRequestedFrom,
           history.records.contains(where: { Self.sampleIndexDistance(newerIndex: $0.timeOffset, olderIndex: requestedFrom) < Self.halfSampleIndexRange })
        {
            sensorIdentity.clearPendingHistoryRequest()
        }

        let nextIndex = (lastRecord.timeOffset + 1) & Self.sampleIndexMask
        guard !Self.isHistoryCaughtUp(nextIndex: nextIndex, latestCurrentIndex: latestCurrentIndex) else {
            sensorIdentity.clearPendingHistoryRequest()
            return nil
        }

        return scheduleHistoryRequest(
            fromIndex: nextIndex,
            currentIndex: latestCurrentIndex,
            reason: .continuation,
            in: &sensorIdentity
        )
    }

    private func scheduleHistoryRequest(
        fromIndex: Int,
        currentIndex: Int,
        reason: MicroTechHistoryRequest.Reason,
        in sensorIdentity: inout MicroTechSensorIdentityState
    ) -> MicroTechHistoryRequest? {
        if sensorIdentity.historyBackfillRequestedFrom == fromIndex &&
            !Self.shouldRetryHistoryBackfill(currentIndex: currentIndex, requestedAt: sensorIdentity.historyBackfillRequestedAtCurrentIndex)
        {
            return nil
        }

        sensorIdentity.historyBackfillRequestedFrom = fromIndex
        sensorIdentity.historyBackfillRequestedAtCurrentIndex = currentIndex
        return MicroTechHistoryRequest(fromIndex: fromIndex, currentIndex: currentIndex, reason: reason)
    }

    private func sendHistoryRequest(_ request: MicroTechHistoryRequest, from sensor: MicroTechSensor) {
        do {
            try sensor.requestHistory(index: request.fromIndex)
            logDeviceCommunication(
                "MicroTech LinX history \(request.reason.logName) requested from=\(request.fromIndex) current=\(request.currentIndex)",
                type: .send
            )
        } catch {
            _ = mutateProtectedState { state in
                guard isCurrentSensor(sensor, in: state.sensorIdentity),
                      state.sensorIdentity.historyBackfillRequestedFrom == request.fromIndex
                else {
                    return
                }
                state.sensorIdentity.clearPendingHistoryRequest()
            }
            logDeviceCommunication(
                "MicroTech LinX history \(request.reason.logName) request failed from=\(request.fromIndex) current=\(request.currentIndex) error=\(String(describing: error))",
                type: .error
            )
        }
    }

    private static func nextHistoryRequestIndex(currentIndex: Int, historySamples: Set<Int>) -> Int? {
        guard currentIndex > linxAidexWarmupMinutes else {
            return nil
        }
        guard !historySamples.isEmpty else {
            return linxAidexWarmupMinutes
        }

        var nearest: Int?
        var nearestDistance: Int?
        for sample in historySamples {
            let distance = sampleIndexDistance(newerIndex: currentIndex, olderIndex: sample)
            guard distance < halfSampleIndexRange else {
                continue
            }
            if nearestDistance == nil || distance < nearestDistance! {
                nearest = sample
                nearestDistance = distance
            }
        }

        guard let nearest, let nearestDistance else {
            return linxAidexWarmupMinutes
        }
        guard nearestDistance > 1 else {
            return nil
        }
        return (nearest + 1) & sampleIndexMask
    }

    private static func isHistoryCaughtUp(nextIndex: Int, latestCurrentIndex: Int?) -> Bool {
        guard let latestCurrentIndex else {
            return false
        }
        let distance = sampleIndexDistance(newerIndex: latestCurrentIndex, olderIndex: nextIndex)
        return distance <= historyCaughtUpDistance || distance >= halfSampleIndexRange
    }

    private static func shouldRetryHistoryBackfill(currentIndex: Int, requestedAt: Int?) -> Bool {
        guard let requestedAt else {
            return true
        }
        return sampleIndexDistance(newerIndex: currentIndex, olderIndex: requestedAt) >= historyRetrySampleDistance
    }

    private func appendHistoryDetail(_ detail: String, to details: inout [String]) {
        guard details.count < Self.maxHistoryRejectionDetailsPerReason else {
            return
        }
        details.append(detail)
    }

    private func appendHistoryRejectionDetails(
        to message: String,
        invalid: [String],
        duplicate: [String],
        tooNew: [String],
        filtered: [String]
    ) -> String {
        var message = message
        if !invalid.isEmpty {
            message += " invalid=[\(invalid.joined(separator: "; "))]"
        }
        if !duplicate.isEmpty {
            message += " duplicate=[\(duplicate.joined(separator: "; "))]"
        }
        if !tooNew.isEmpty {
            message += " tooNew=[\(tooNew.joined(separator: "; "))]"
        }
        if !filtered.isEmpty {
            message += " filtered=[\(filtered.joined(separator: "; "))]"
        }
        return message
    }

    private static func sampleIndexDistance(newerIndex: Int, olderIndex: Int) -> Int {
        (newerIndex - olderIndex + sampleIndexModulus) & sampleIndexMask
    }

    private static func isSampleNumber(_ sampleNumber: Int, notNewerThan latestSampleNumber: Int) -> Bool {
        let distanceFromLatest = sampleIndexDistance(newerIndex: sampleNumber, olderIndex: latestSampleNumber)
        return distanceFromLatest == 0 || distanceFromLatest >= halfSampleIndexRange
    }

    private static func sampleIndexDistanceIfOrdered(newerIndex: Int, olderIndex: Int) -> Int? {
        let distance = sampleIndexDistance(newerIndex: newerIndex, olderIndex: olderIndex)
        guard distance < halfSampleIndexRange else {
            return nil
        }
        return distance
    }

    private func registerDelegateQueue(_ queue: DispatchQueue?) {
        queue?.setSpecific(key: delegateQueueSpecificKey, value: delegateQueueSpecificValue)
    }

    private func startDateToFilterNewData() -> Date? {
        if DispatchQueue.getSpecific(key: delegateQueueSpecificKey) == delegateQueueSpecificValue {
            return cgmManagerDelegate?.startDateToFilterNewData(for: self)
        }

        return delegate.call { delegate in
            delegate?.startDateToFilterNewData(for: self)
        }
    }

    private func device(for state: MicroTechCGMManagerState) -> HKDevice {
        HKDevice(
            name: state.deviceName ?? state.sensorSerial ?? "MicroTech LinX",
            manufacturer: "MicroTech Medical",
            model: "LinX",
            hardwareVersion: nil,
            firmwareVersion: nil,
            softwareVersion: nil,
            localIdentifier: state.remoteIdentifier?.uuidString,
            udiDeviceIdentifier: nil
        )
    }

    private static func sensorSerial(from deviceNameOrSerial: String) -> String {
        guard let separator = deviceNameOrSerial.lastIndex(of: "-") else {
            return deviceNameOrSerial
        }

        let serialStart = deviceNameOrSerial.index(after: separator)
        guard serialStart < deviceNameOrSerial.endIndex else {
            return deviceNameOrSerial
        }
        return String(deviceNameOrSerial[serialStart...])
    }

    private static func advertisedSensorSerial(from deviceName: String) -> String? {
        guard deviceName.localizedCaseInsensitiveContains("LinX") ||
            deviceName.localizedCaseInsensitiveContains("AiDEX") ||
            deviceName.localizedCaseInsensitiveContains("BWCGM")
        else {
            return nil
        }

        let serial = sensorSerial(from: deviceName).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !serial.isEmpty, serial != deviceName else {
            return nil
        }
        return serial
    }

    private static func broadcastSensorSerial(
        from advertisement: MicroTechBroadcastAdvertisement,
        currentState: MicroTechCGMManagerState
    ) -> String? {
        for name in [advertisement.localName, advertisement.peripheralName, currentState.deviceName] {
            guard let name,
                  let serial = advertisedSensorSerial(from: name)
            else {
                continue
            }
            return serial
        }

        if let sensorSerial = currentState.sensorSerial,
           !sensorSerial.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return sensorSerial
        }
        return nil
    }

    private static func failedRemoteIdentifier(from error: MicroTechBluetoothManagerError) -> UUID? {
        switch error {
        case .connectTimeout(let identifier):
            return identifier
        case .connectFailed(let identifier, _):
            return identifier
        case .configureTimeout(let identifier):
            return identifier
        case .scanTimeout(let identifier):
            return identifier
        case .bluetoothUnavailable:
            return nil
        }
    }

    private static func packetTypeDescription(_ data: Data) -> String {
        guard let packetType = data.first else {
            return "nil"
        }
        return String(format: "0x%02X", packetType)
    }

    private static let glucoseUnit = HKUnit
        .gramUnit(with: .milli)
        .unitDivided(by: .literUnit(with: .deci))

    private static let linxAidexWarmupMinutes = 60
    private static let historyCaughtUpDistance = 2
    private static let historyRetrySampleDistance = 5
    private static let staleReadingReconnectInterval: TimeInterval = 15 * 60
    private static let reconnectRecoveryInterval: TimeInterval = 60
    private static let consecutiveSensorErrorReconnectThreshold = 3
    private static let savedIdentifierFallbackFailureThreshold = 2
    private static let maxHistoryRejectionDetailsPerReason = 3
    private static let sampleIndexModulus = 65536
    private static let sampleIndexMask = 0xffff
    private static let halfSampleIndexRange = sampleIndexModulus / 2

    func connectDiscoveredSensor(
        peripheralSession: MicroTechPeripheralSession,
        expectedManager: MicroTechBluetoothManaging? = nil
    ) {
        if let expectedManager,
           !isCurrentBluetoothManager(expectedManager)
        {
            logDeviceCommunication("MicroTech LinX ignored callback=ready reason=retiredBluetoothManager", type: .connection)
            peripheralSession.disconnect()
            return
        }
        guard let sensorSerial = Self.advertisedSensorSerial(from: peripheralSession.deviceName) else {
            logDeviceCommunication("MicroTech LinX rejected discovered device \(peripheralSession.deviceName) because no sensor serial could be read", type: .connection)
            peripheralSession.disconnect()
            return
        }

        let session = MicroTechAidexSession(
            remoteIdentifier: peripheralSession.deviceIdentifier,
            deviceName: peripheralSession.deviceName,
            sensorSerial: sensorSerial
        )
        let sensor = MicroTechSensor(session: session, peripheralSession: peripheralSession)
        sensor.delegate = self

        var shouldStartSensor = false
        var startEligibilityIdentifier: UUID?
        var sensorToRetire: MicroTechSensor?
        let stateChange = mutateProtectedState { protectedState in
            if let expectedManager,
               !isCurrentBluetoothManager(expectedManager, in: protectedState)
            {
                return
            }
            guard !protectedState.sensorIdentity.isDeleted else {
                return
            }

            let isNewSensor = protectedState.state.sensorSerial != sensorSerial
            sensorToRetire = protectedState.sensorIdentity.activeSensor
            protectedState.sensorIdentity.retireActiveSensor()
            if isNewSensor {
                protectedState.state.activationTime = nil
                protectedState.state.lastReadingDate = nil
                protectedState.state.latestReading = nil
                protectedState.state.latestSampleNumber = nil
                protectedState.state.hasConnectedSensorSession = false
                protectedState.state.lastConnectionErrorDescription = nil
                protectedState.sensorIdentity.pendingReconnectRecoveryReason = nil
                protectedState.sensorIdentity.resetHistoryTracking()
            }

            shouldStartSensor = true
            protectedState.sensorIdentity.restore(sensor)
            protectedState.sensorIdentity.activeSensor = sensor
            protectedState.sensorIdentity.startEligibilityIdentifier = UUID()
            startEligibilityIdentifier = protectedState.sensorIdentity.startEligibilityIdentifier
            protectedState.sensorIdentity.activeSensorConnectedAt = nil
            protectedState.sensorIdentity.staleConnectionWatchdogIdentifier = UUID()
            protectedState.sensorIdentity.consecutiveSensorErrorCount = 0
            protectedState.sensorIdentity.savedIdentifierFailureCount = 0
            protectedState.state.remoteIdentifier = session.remoteIdentifier
            protectedState.state.deviceName = session.deviceName
            protectedState.state.sensorSerial = session.sensorSerial
            protectedState.state.lastConnectionErrorDescription = nil
            // Delegate assignment is performed after the protected state is released.
        }
        sensorToRetire?.retire()
        notifyStateDidChange(from: stateChange.oldState, to: stateChange.newState)

        guard shouldStartSensor, let startEligibilityIdentifier else {
            logDeviceCommunication(
                "MicroTech LinX ignored callback=ready reason=retiredBluetoothManagerOrDeleted",
                type: .connection
            )
            peripheralSession.disconnect()
            return
        }

        logDeviceCommunication(
            "MicroTech LinX discovered device \(peripheralSession.deviceName), identifier \(peripheralSession.deviceIdentifier), sensor serial \(sensorSerial)",
            type: .connection
        )

        let generation = readProtectedState { state -> MicroTechBluetoothManagerGeneration? in
            guard isCurrentSensor(sensor, in: state.sensorIdentity),
                  let generation = state.bluetoothManager,
                  expectedManager == nil || generation.manager === expectedManager
            else {
                return nil
            }
            return generation
        }
        guard let generation else {
            peripheralSession.disconnect()
            return
        }
        generation.manager.delegate = sensor

        sensorStartScheduler { [weak self] in
            guard let self else {
                sensor.retire()
                return
            }
            let isEligible = self.readProtectedState { state in
                self.isCurrentSensor(sensor, in: state.sensorIdentity) &&
                    state.sensorIdentity.startEligibilityIdentifier == startEligibilityIdentifier &&
                    state.bluetoothManager?.id == generation.id &&
                    state.bluetoothManager?.manager === generation.manager &&
                    state.state.connectionMode == .direct &&
                    !state.reconnectRecoveryState.isShuttingDown
            }
            guard isEligible else {
                sensor.retire()
                return
            }
            self.beforeSensorStart()
            do {
                try sensor.start()
            } catch {
                self.logDeviceCommunication("MicroTech LinX sensor start failed: \(String(describing: error))", type: .error)
            }
        }
    }

    func handleBluetoothShouldConnect(
        from manager: MicroTechBluetoothManaging,
        deviceName: String,
        identifier: UUID
    ) -> Bool {
        callbackProcessingBarrier()
        let currentState = readProtectedState { state -> MicroTechCGMManagerState? in
            guard isCurrentBluetoothManager(manager, in: state) else {
                return nil
            }
            return state.state
        }
        guard let currentState else {
            logDeviceCommunication("MicroTech LinX ignored callback=shouldConnect reason=retiredBluetoothManager", type: .connection)
            return false
        }
        return shouldConnectToMicroTechDevice(
            deviceName: deviceName,
            identifier: identifier,
            currentState: currentState
        )
    }

    func handleBluetoothReady(
        from manager: MicroTechBluetoothManaging,
        peripheralSession: MicroTechPeripheralSession
    ) {
        callbackProcessingBarrier()
        connectDiscoveredSensor(peripheralSession: peripheralSession, expectedManager: manager)
    }

    func handleBluetoothData(
        from manager: MicroTechBluetoothManaging,
        value: Data,
        characteristic: CBUUID,
        session: MicroTechPeripheralSession
    ) {
        callbackProcessingBarrier()
        guard isCurrentBluetoothManager(manager) else {
            logDeviceCommunication("MicroTech LinX ignored callback=data reason=retiredBluetoothManager", type: .connection)
            return
        }
    }

    func handleBluetoothDisconnect(
        from manager: MicroTechBluetoothManaging,
        session: MicroTechPeripheralSession
    ) {
        callbackProcessingBarrier()
        var didAcceptSource = false
        var recoveryIdentifier: UUID?
        let stateChange = mutateProtectedState { state in
            guard isCurrentBluetoothManager(manager, in: state) else {
                return
            }
            didAcceptSource = true
            state.sensorIdentity.activeSensorConnectedAt = nil
            state.sensorIdentity.staleConnectionWatchdogIdentifier = UUID()
            recoveryIdentifier = claimReconnectRecoveryIfNeeded(reason: "Bluetooth disconnect", in: &state)
        }
        guard didAcceptSource else {
            logDeviceCommunication("MicroTech LinX ignored callback=disconnect reason=retiredBluetoothManager", type: .connection)
            return
        }
        notifyStateDidChange(from: stateChange.oldState, to: stateChange.newState)
        if let recoveryIdentifier {
            scheduleReconnectRecovery(identifier: recoveryIdentifier, reason: "Bluetooth disconnect")
        }
        scheduleResumeSavedSensorScanIfNeeded(reason: "Bluetooth disconnect", expectedManager: manager)
    }

    func handleBluetoothBroadcast(
        from manager: MicroTechBluetoothManaging,
        advertisement: MicroTechBroadcastAdvertisement
    ) {
        callbackProcessingBarrier()
        do {
            let broadcastReading = try MicroTechAidexBroadcastParser.parseAdvertisementData(advertisement.advertisementData)
            let result = acceptBroadcastReading(
                broadcastReading,
                advertisement: advertisement,
                expectedManager: manager
            )
            guard result.sourceAccepted else {
                logDeviceCommunication("MicroTech LinX ignored callback=broadcast reason=retiredBluetoothManager", type: .connection)
                return
            }
            logBroadcastParsed(broadcastReading, advertisement: advertisement)
            notifyDelegateOfReadingResult(result.sample.map { .newData([$0]) } ?? .noData)
        } catch {
            guard isCurrentBluetoothManager(manager) else {
                logDeviceCommunication("MicroTech LinX ignored callback=broadcast reason=retiredBluetoothManager", type: .connection)
                return
            }
            logBroadcastParseError(error, advertisement: advertisement)
            notifyDelegateOfReadingResult(.noData)
        }
    }

    func handleBluetoothFailure(from manager: MicroTechBluetoothManaging, error: Error) {
        callbackProcessingBarrier()
        guard isCurrentBluetoothManager(manager) else {
            logDeviceCommunication("MicroTech LinX ignored callback=failure reason=retiredBluetoothManager", type: .connection)
            return
        }
        recordBluetoothFailure(error, expectedManager: manager)
    }
}

private enum MicroTechDeviceLogDestination {
    case onboarding(MicroTechOnboardingDeviceLogHandler)
    case formalDelegate
    case systemOnly
}

extension MicroTechCGMManager: MicroTechBluetoothManagerDelegate {
    public func microTechBluetoothManager(_ manager: MicroTechBluetoothManager, shouldConnectToDeviceName deviceName: String, identifier: UUID) -> Bool {
        handleBluetoothShouldConnect(from: manager, deviceName: deviceName, identifier: identifier)
    }

    public func microTechBluetoothManager(_ manager: MicroTechBluetoothManager, didReady peripheralSession: MicroTechPeripheralSession) {
        handleBluetoothReady(from: manager, peripheralSession: peripheralSession)
    }

    public func microTechBluetoothManager(_ manager: MicroTechBluetoothManager, didReceive value: Data, for characteristic: CBUUID, session: MicroTechPeripheralSession) {
        handleBluetoothData(from: manager, value: value, characteristic: characteristic, session: session)
    }

    public func microTechBluetoothManager(_ manager: MicroTechBluetoothManager, didDisconnect session: MicroTechPeripheralSession) {
        handleBluetoothDisconnect(from: manager, session: session)
    }

    public func microTechBluetoothManager(_ manager: MicroTechBluetoothManager, didDiscoverBroadcast advertisement: MicroTechBroadcastAdvertisement) {
        handleBluetoothBroadcast(from: manager, advertisement: advertisement)
    }

    public func microTechBluetoothManager(_ manager: MicroTechBluetoothManager, didFailWith error: Error) {
        handleBluetoothFailure(from: manager, error: error)
    }
}

extension MicroTechCGMManager: MicroTechSensorDelegate {
    public func microTechSensorDidConnect(_ sensor: MicroTechSensor, session: MicroTechAidexSession) {
        callbackProcessingBarrier()
        var didAccept = false
        var shouldStartSensor = false
        let stateChange = mutateProtectedState { state in
            didAccept = acceptSensorConnection(sensor, session: session, in: &state)
            shouldStartSensor = didAccept &&
                state.state.activationTime == nil &&
                state.state.latestSampleNumber == nil
        }

        guard didAccept else {
            return
        }

        cancelReconnectRecovery(reason: "handshake")
        notifyStateDidChange(from: stateChange.oldState, to: stateChange.newState)
        scheduleStaleConnectionWatchdogIfNeeded(reason: "sensor connect")
        if shouldStartSensor {
            do {
                try sensor.startSensor(at: Date())
                logDeviceCommunication("MicroTech LinX sensor activation queued", type: .connection)
            } catch {
                let failureStateChange = mutateProtectedState { state in
                    guard isCurrentSensor(sensor, in: state.sensorIdentity) else {
                        return
                    }
                    state.state.lastConnectionErrorDescription = "Sensor activation failed: \(String(describing: error))"
                }
                notifyStateDidChange(from: failureStateChange.oldState, to: failureStateChange.newState)
                logDeviceCommunication("MicroTech LinX sensor activation failed: \(String(describing: error))", type: .error)
                notifyDelegateOfReadingResult(.error(error))
            }
        }
    }

    public func microTechSensorDidDisconnect(_ sensor: MicroTechSensor) {
        callbackProcessingBarrier()
        var shouldNotify = false
        var recoveryIdentifier: UUID?
        lockedManagerState.mutate { state in
            shouldNotify = isCurrentSensor(sensor, in: state.sensorIdentity)
            guard shouldNotify else {
                return
            }

            state.sensorIdentity.activeSensorConnectedAt = nil
            state.sensorIdentity.staleConnectionWatchdogIdentifier = UUID()
            recoveryIdentifier = claimReconnectRecoveryIfNeeded(reason: "sensor disconnect", in: &state)
        }

        guard shouldNotify else {
            return
        }

        delegate.notify { delegate in
            delegate?.cgmManager(self, didUpdate: self.cgmManagerStatus)
        }
        if let recoveryIdentifier {
            scheduleReconnectRecovery(identifier: recoveryIdentifier, reason: "sensor disconnect")
        }
        scheduleResumeSavedSensorScanIfNeeded(
            reason: "sensor disconnect",
            expectedSensor: sensor
        )
    }

    public func microTechSensor(_ sensor: MicroTechSensor, didRead reading: MicroTechGlucoseReading) {
        callbackProcessingBarrier()
        var didHandleCurrentSensor = false
        var result: CGMReadingResult?
        var sample: NewGlucoseSample?
        var logMessage: String?
        var historyRequest: MicroTechHistoryRequest?
        let filterStartDate = startDateToFilterNewData()
        let stateChange = mutateProtectedState { state in
            guard isCurrentSensor(sensor, in: state.sensorIdentity) else {
                return
            }
            didHandleCurrentSensor = true

            guard reading.isValidForTherapy else {
                result = .noData
                logMessage = "current rejected serial=\(reading.sensorSerial) sample=\(reading.sampleNumber) value=\(reading.glucoseMgdl) quality=\(reading.quality) packetType=\(Self.packetTypeDescription(reading.rawBytes)) rawHex=\(reading.rawBytes.microTechHexadecimalString) reason=notTherapyValid"
                return
            }

            if let filterStartDate, reading.receivedAt < filterStartDate {
                result = .noData
                logMessage = "current rejected serial=\(reading.sensorSerial) sample=\(reading.sampleNumber) value=\(reading.glucoseMgdl) packetType=\(Self.packetTypeDescription(reading.rawBytes)) rawHex=\(reading.rawBytes.microTechHexadecimalString) at=\(reading.receivedAt) startDate=\(filterStartDate) reason=beforeStartDate"
                return
            }

            if state.state.sensorSerial == reading.sensorSerial,
               let latestSampleNumber = state.state.latestSampleNumber,
               Self.isSampleNumber(reading.sampleNumber, notNewerThan: latestSampleNumber)
            {
                result = .noData
                logMessage = "current rejected serial=\(reading.sensorSerial) sample=\(reading.sampleNumber) latest=\(latestSampleNumber) packetType=\(Self.packetTypeDescription(reading.rawBytes)) rawHex=\(reading.rawBytes.microTechHexadecimalString) reason=duplicateOrOld"
                return
            }

            state.state.sensorSerial = reading.sensorSerial
            state.state.lastReadingDate = reading.receivedAt
            state.state.latestReading = reading
            state.state.latestSampleNumber = reading.sampleNumber
            state.state.lastConnectionErrorDescription = nil
            state.sensorIdentity.consecutiveSensorErrorCount = 0
            let recoveryReason = state.sensorIdentity.pendingReconnectRecoveryReason
            state.sensorIdentity.pendingReconnectRecoveryReason = nil
            sample = makeSample(from: reading, state: state.state)
            historyRequest = scheduleHistoryBackfillIfNeeded(
                currentIndex: reading.sampleNumber,
                in: &state.sensorIdentity
            )
            if let recoveryReason {
                logMessage = "current accepted serial=\(reading.sensorSerial) sample=\(reading.sampleNumber) value=\(reading.glucoseMgdl) packetType=\(Self.packetTypeDescription(reading.rawBytes)) rawHex=\(reading.rawBytes.microTechHexadecimalString) recoveredAfterReconnect reason=\(recoveryReason) at=\(reading.receivedAt)"
            } else {
                logMessage = "current accepted serial=\(reading.sensorSerial) sample=\(reading.sampleNumber) value=\(reading.glucoseMgdl) packetType=\(Self.packetTypeDescription(reading.rawBytes)) rawHex=\(reading.rawBytes.microTechHexadecimalString) at=\(reading.receivedAt)"
            }
        }

        guard didHandleCurrentSensor else {
            return
        }
        notifyStateDidChange(from: stateChange.oldState, to: stateChange.newState)
        if let logMessage {
            logDeviceCommunication("MicroTech LinX \(logMessage)", type: .receive)
        }
        if let historyRequest {
            sendHistoryRequest(historyRequest, from: sensor)
        }

        if let sample {
            scheduleStaleConnectionWatchdogIfNeeded(reason: "current reading")
            notifyDelegateOfReadingResult(.newData([sample]))
        } else if let result {
            notifyDelegateOfReadingResult(result)
        }
    }

    public func microTechSensor(_ sensor: MicroTechSensor, didReadHistory history: MicroTechAidexHistoryPacket) {
        callbackProcessingBarrier()
        var didHandleCurrentSensor = false
        var samples: [NewGlucoseSample] = []
        var logMessage: String?
        var historyRequest: MicroTechHistoryRequest?
        let communicationDate = Date()
        let filterStartDate = startDateToFilterNewData()
        let stateChange = mutateProtectedState { state in
            guard isCurrentSensor(sensor, in: state.sensorIdentity),
                  let sensorSerial = state.state.sensorSerial
            else {
                return
            }
            didHandleCurrentSensor = true

            let latestReading = state.state.latestReading
            let latestSampleNumber = state.state.latestSampleNumber
            let activationTime = state.state.activationTime
            state.sensorIdentity.consecutiveSensorErrorCount = 0
            guard latestReading != nil || activationTime != nil else {
                logMessage = "history skipped serial=\(sensorSerial) records=\(history.records.count) start=\(history.startTimeOffset) reason=noCurrentOrActivationTime"
                return
            }

            var invalidCount = 0
            var duplicateCount = 0
            var tooNewCount = 0
            var filteredCount = 0
            var invalidDetails: [String] = []
            var duplicateDetails: [String] = []
            var tooNewDetails: [String] = []
            var filteredDetails: [String] = []
            for record in history.records {
                guard record.isValidForTherapy else {
                    invalidCount += 1
                    appendHistoryDetail(
                        "sample=\(record.timeOffset) value=\(record.glucose) quality=\(record.quality) raw=\(record.rawValue)",
                        to: &invalidDetails
                    )
                    continue
                }

                var minutesBeforeLatest: Int?
                if let latestSampleNumber {
                    guard let distance = Self.sampleIndexDistanceIfOrdered(
                        newerIndex: latestSampleNumber,
                        olderIndex: record.timeOffset
                    ), distance > 0 else {
                        tooNewCount += 1
                        appendHistoryDetail("sample=\(record.timeOffset) latest=\(latestSampleNumber)", to: &tooNewDetails)
                        continue
                    }
                    minutesBeforeLatest = distance
                }

                guard !state.sensorIdentity.emittedHistorySampleNumbers.contains(record.timeOffset) else {
                    duplicateCount += 1
                    appendHistoryDetail("sample=\(record.timeOffset)", to: &duplicateDetails)
                    continue
                }

                let sampleDate: Date
                if let latestReading, let minutesBeforeLatest {
                    sampleDate = latestReading.receivedAt.addingTimeInterval(-Double(minutesBeforeLatest) * 60)
                } else if let activationTime {
                    sampleDate = activationTime.addingTimeInterval(Double(record.timeOffset) * 60)
                } else {
                    continue
                }

                if let filterStartDate, sampleDate < filterStartDate {
                    filteredCount += 1
                    appendHistoryDetail("sample=\(record.timeOffset) at=\(sampleDate) startDate=\(filterStartDate)", to: &filteredDetails)
                    continue
                }

                samples.append(makeSample(
                    sensorSerial: sensorSerial,
                    sampleNumber: record.timeOffset,
                    glucoseMgdl: record.glucose,
                    date: sampleDate,
                    state: state.state
                ))
                state.sensorIdentity.emittedHistorySampleNumbers.insert(record.timeOffset)
            }
            if !samples.isEmpty {
                state.state.lastReadingDate = communicationDate
                state.state.lastConnectionErrorDescription = nil
            }
            historyRequest = scheduleNextHistoryRequestIfNeeded(
                history: history,
                latestCurrentIndex: latestSampleNumber,
                in: &state.sensorIdentity
            )
            let anchor = latestReading == nil ? "activationTime" : "current"
            var historyLogMessage = "history processed serial=\(sensorSerial) records=\(history.records.count) accepted=\(samples.count) invalid=\(invalidCount) duplicate=\(duplicateCount) tooNew=\(tooNewCount) filtered=\(filteredCount) start=\(history.startTimeOffset) anchor=\(anchor)"
            historyLogMessage = appendHistoryRejectionDetails(
                to: historyLogMessage,
                invalid: invalidDetails,
                duplicate: duplicateDetails,
                tooNew: tooNewDetails,
                filtered: filteredDetails
            )
            logMessage = historyLogMessage
        }

        guard didHandleCurrentSensor else {
            return
        }
        notifyStateDidChange(from: stateChange.oldState, to: stateChange.newState)
        if let logMessage {
            logDeviceCommunication("MicroTech LinX \(logMessage)", type: .receive)
        }
        if let historyRequest {
            sendHistoryRequest(historyRequest, from: sensor)
        }

        guard !samples.isEmpty else {
            notifyDelegateOfReadingResult(.noData)
            return
        }

        scheduleStaleConnectionWatchdogIfNeeded(reason: "history reading")
        notifyDelegateOfReadingResult(.newData(samples))
    }

    public func microTechSensor(_ sensor: MicroTechSensor, didActivateAt activationTime: Date) {
        callbackProcessingBarrier()
        var didAccept = false
        let stateChange = mutateProtectedState { state in
            guard isCurrentSensor(sensor, in: state.sensorIdentity) else {
                return
            }
            didAccept = true
            state.state.activationTime = activationTime
            state.state.lastConnectionErrorDescription = nil
            state.sensorIdentity.consecutiveSensorErrorCount = 0
        }
        notifyStateDidChange(from: stateChange.oldState, to: stateChange.newState)
        if didAccept {
            logDeviceCommunication("MicroTech LinX sensor activation time \(activationTime)", type: .connection)
        }
    }

    public func microTechSensor(_ sensor: MicroTechSensor, didIgnorePacketType packetType: UInt8, length: Int, hexPrefix rawHex: String) {
        callbackProcessingBarrier()
        let shouldLog = readProtectedState { state in
            isCurrentSensor(sensor, in: state.sensorIdentity)
        }

        guard shouldLog else {
            return
        }

        logDeviceCommunication(
            "MicroTech LinX ignored unsupported packet type \(String(format: "0x%02X", packetType)) len=\(length) rawHex=\(rawHex)",
            type: .receive
        )
    }

    public func microTechSensor(_ sensor: MicroTechSensor, didLog message: String, type: MicroTechSensorLogType) {
        callbackProcessingBarrier()
        let shouldLog = readProtectedState { state in
            isCurrentSensor(sensor, in: state.sensorIdentity)
        }

        guard shouldLog else {
            return
        }

        logDeviceCommunication("MicroTech LinX \(message)", type: type.deviceLogEntryType)
    }

    public func microTechSensor(_ sensor: MicroTechSensor, didError error: Error) {
        callbackProcessingBarrier()
        if error is MicroTechBluetoothManagerError {
            recordBluetoothFailure(error, expectedSensor: sensor)
            return
        }

        var shouldNotify = false
        var bluetoothManager: MicroTechBluetoothManaging?
        var consecutiveErrorCount = 0
        var recoveryIdentifier: UUID?
        let stateChange = mutateProtectedState { state in
            guard isCurrentSensor(sensor, in: state.sensorIdentity) else {
                return
            }

            shouldNotify = true
            state.state.lastConnectionErrorDescription = "Sensor error: \(String(describing: error))"
            state.sensorIdentity.consecutiveSensorErrorCount += 1
            consecutiveErrorCount = state.sensorIdentity.consecutiveSensorErrorCount
            if consecutiveErrorCount >= Self.consecutiveSensorErrorReconnectThreshold {
                bluetoothManager = state.bluetoothManager?.manager
                state.sensorIdentity.consecutiveSensorErrorCount = 0
                state.sensorIdentity.activeSensorConnectedAt = nil
                state.sensorIdentity.staleConnectionWatchdogIdentifier = UUID()
                recoveryIdentifier = claimReconnectRecoveryIfNeeded(
                    reason: "\(consecutiveErrorCount) consecutive sensor errors",
                    in: &state
                )
            }
        }

        guard shouldNotify else {
            return
        }

        notifyStateDidChange(from: stateChange.oldState, to: stateChange.newState)
        logDeviceCommunication("MicroTech LinX sensor error: \(String(describing: error)) consecutive=\(consecutiveErrorCount)", type: .error)
        if let bluetoothManager {
            logDeviceCommunication("MicroTech LinX restarting connection after \(consecutiveErrorCount) consecutive sensor errors", type: .connection)
            if let recoveryIdentifier {
                scheduleReconnectRecovery(
                    identifier: recoveryIdentifier,
                    reason: "\(consecutiveErrorCount) consecutive sensor errors"
                )
            }
            bluetoothManager.disconnect()
            scheduleResumeSavedSensorScanIfNeeded(
                reason: "\(consecutiveErrorCount) consecutive sensor errors",
                expectedSensor: sensor
            )
        }
        notifyDelegateOfReadingResult(.error(error))
    }
}

private extension MicroTechBluetoothLogType {
    var deviceLogEntryType: DeviceLogEntryType {
        switch self {
        case .connection:
            return .connection
        case .send:
            return .send
        case .receive:
            return .receive
        case .error:
            return .error
        }
    }
}

private extension MicroTechSensorLogType {
    var deviceLogEntryType: DeviceLogEntryType {
        switch self {
        case .connection:
            return .connection
        case .send:
            return .send
        case .receive:
            return .receive
        case .error:
            return .error
        }
    }
}

private extension MicroTechAidexHistoryRecord {
    var isValidForTherapy: Bool {
        timeOffset >= 0 && glucose >= 40 && glucose <= 400 && quality == 0
    }
}

private struct MicroTechHistoryRequest {
    enum Reason {
        case backfill
        case continuation

        var logName: String {
            switch self {
            case .backfill:
                return "backfill"
            case .continuation:
                return "continuation"
            }
        }
    }

    let fromIndex: Int
    let currentIndex: Int
    let reason: Reason
}

private struct MicroTechCGMManagerProtectedState {
    var state: MicroTechCGMManagerState
    var sensorIdentity = MicroTechSensorIdentityState()
    var bluetoothManager: MicroTechBluetoothManagerGeneration?
    var reconnectRecoveryState: MicroTechReconnectRecoveryState = .idle
}

private struct MicroTechBluetoothManagerGeneration {
    let id: UUID
    let manager: MicroTechBluetoothManaging
}

private enum MicroTechReconnectRecoveryState {
    case idle
    case timing(id: UUID)
    case shuttingDown(id: UUID)
}

private extension MicroTechReconnectRecoveryState {
    var isShuttingDown: Bool {
        if case .shuttingDown = self {
            return true
        }
        return false
    }
}

private struct MicroTechSensorIdentityState {
    var activeSensor: MicroTechSensor?
    var startEligibilityIdentifier = UUID()
    let retiredSensors = NSHashTable<MicroTechSensor>(options: [.weakMemory, .objectPointerPersonality])
    var emittedHistorySampleNumbers: Set<Int> = []
    var historyBackfillRequestedFrom: Int?
    var historyBackfillRequestedAtCurrentIndex: Int?
    var activeSensorConnectedAt: Date?
    var staleConnectionWatchdogIdentifier = UUID()
    var consecutiveSensorErrorCount = 0
    var savedIdentifierFailureCount = 0
    var pendingReconnectRecoveryReason: String?
    var isDeleted = false

    func isRetired(_ sensor: MicroTechSensor) -> Bool {
        retiredSensors.contains(sensor)
    }

    mutating func retireActiveSensor() {
        guard let activeSensor else {
            return
        }
        retiredSensors.add(activeSensor)
        startEligibilityIdentifier = UUID()
    }

    mutating func restore(_ sensor: MicroTechSensor) {
        retiredSensors.remove(sensor)
    }

    mutating func resetForSensorChange() {
        retireActiveSensor()
        activeSensor = nil
        emittedHistorySampleNumbers.removeAll()
        clearPendingHistoryRequest()
        activeSensorConnectedAt = nil
        staleConnectionWatchdogIdentifier = UUID()
        consecutiveSensorErrorCount = 0
        savedIdentifierFailureCount = 0
        pendingReconnectRecoveryReason = nil
    }

    mutating func resetHistoryTracking() {
        emittedHistorySampleNumbers.removeAll()
        clearPendingHistoryRequest()
    }

    mutating func clearPendingHistoryRequest() {
        historyBackfillRequestedFrom = nil
        historyBackfillRequestedAtCurrentIndex = nil
    }
}

private enum MicroTechPendingPeripheralSessionError: Error {
    case notConnected
}

private final class MicroTechPendingPeripheralSession: MicroTechPeripheralSession {
    let deviceIdentifier: UUID
    let deviceName: String

    init(session: MicroTechAidexSession) {
        deviceIdentifier = session.remoteIdentifier
        deviceName = session.deviceName
    }

    func subscribe(_ characteristic: CBUUID) throws {
        throw MicroTechPendingPeripheralSessionError.notConnected
    }

    func write(_ value: Data, to characteristic: CBUUID) throws {
        throw MicroTechPendingPeripheralSessionError.notConnected
    }

    func read(_ characteristic: CBUUID) throws -> Data {
        throw MicroTechPendingPeripheralSessionError.notConnected
    }

    func disconnect() {
    }
}
