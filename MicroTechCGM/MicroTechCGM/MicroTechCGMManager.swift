import CoreBluetooth
import Foundation
import HealthKit
import LoopKit
import os.log

public final class MicroTechCGMManager: CGMManager {
    private let lockedManagerState: Locked<MicroTechCGMManagerProtectedState>
    private let delegate = WeakSynchronizedDelegate<CGMManagerDelegate>()
    private let statusObservers = WeakSynchronizedSet<CGMManagerStatusObserver>()
    private let delegateQueueSpecificKey = DispatchSpecificKey<UUID>()
    private let delegateQueueSpecificValue = UUID()
    private let bluetoothManagerFactory: () -> MicroTechBluetoothManaging
    private let bluetoothRetryScheduler: (@escaping () -> Void) -> Void
    private let staleConnectionScheduler: (TimeInterval, @escaping () -> Void) -> Void
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
            delegate.delegate = newValue
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
        readProtectedState { state in
            state.bluetoothManager?.isScanning == true
        }
    }

    public var isConnected: Bool {
        readProtectedState { state in
            state.bluetoothManager?.isConnected == true
        }
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
        bluetoothManagerFactory = { MicroTechBluetoothManager() }
        bluetoothRetryScheduler = { retry in
            DispatchQueue.global(qos: .utility).async(execute: retry)
        }
        staleConnectionScheduler = { delay, watchdog in
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + delay, execute: watchdog)
        }
        dateProvider = { Date() }
        resumeScanWhenDelegateQueueConfigured = false
        lockedManagerState = Locked(MicroTechCGMManagerProtectedState(state: MicroTechCGMManagerState()))
        registerDelegateQueue(delegate.queue)
    }

    init(
        state: MicroTechCGMManagerState,
        bluetoothManagerFactory: @escaping () -> MicroTechBluetoothManaging = { MicroTechBluetoothManager() },
        bluetoothRetryScheduler: @escaping (@escaping () -> Void) -> Void = { retry in
            DispatchQueue.global(qos: .utility).async(execute: retry)
        },
        staleConnectionScheduler: @escaping (TimeInterval, @escaping () -> Void) -> Void = { delay, watchdog in
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + delay, execute: watchdog)
        },
        resumeScanWhenDelegateQueueConfigured: Bool = false,
        dateProvider: @escaping () -> Date = { Date() }
    ) {
        self.bluetoothManagerFactory = bluetoothManagerFactory
        self.bluetoothRetryScheduler = bluetoothRetryScheduler
        self.staleConnectionScheduler = staleConnectionScheduler
        self.dateProvider = dateProvider
        self.resumeScanWhenDelegateQueueConfigured = resumeScanWhenDelegateQueueConfigured
        lockedManagerState = Locked(MicroTechCGMManagerProtectedState(state: state))
        registerDelegateQueue(delegate.queue)
    }

    public required init?(rawState: RawStateValue) {
        let restoredState = MicroTechCGMManagerState(rawValue: rawState)
        bluetoothManagerFactory = { MicroTechBluetoothManager() }
        bluetoothRetryScheduler = { retry in
            DispatchQueue.global(qos: .utility).async(execute: retry)
        }
        staleConnectionScheduler = { delay, watchdog in
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + delay, execute: watchdog)
        }
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
        let stateChange = mutateProtectedState { protectedState in
            let isNewSensor = protectedState.state.sensorSerial != normalizedSerial
            let deviceNameChanged = protectedState.state.deviceName != normalizedDeviceName

            if isNewSensor || deviceNameChanged {
                protectedState.state.remoteIdentifier = nil
            }
            if isNewSensor {
                protectedState.state.activationTime = nil
                protectedState.state.lastReadingDate = nil
                protectedState.state.latestReading = nil
                protectedState.state.latestSampleNumber = nil
                protectedState.state.hasConnectedSensorSession = false
                protectedState.state.lastConnectionErrorDescription = nil
                protectedState.sensorIdentity = MicroTechSensorIdentityState()
            }

            protectedState.state.deviceName = normalizedDeviceName
            protectedState.state.sensorSerial = normalizedSerial
        }
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
        if disconnectStaleConnectedSensorIfNeeded() {
            completion(.noData)
            return
        }

        scanForSensor(clearingConnectionError: false)
        completion(.noData)
    }

    @discardableResult
    public func scanForSensor() -> Bool {
        scanForSensor(clearingConnectionError: true)
    }

    @discardableResult
    private func scanForSensor(clearingConnectionError: Bool) -> Bool {
        let currentState = state

        var bluetoothManager: MicroTechBluetoothManaging?
        var shouldStartScan = false
        var shouldRefreshConnectedPeripheral = false
        var scanLogMessage: String?

        let stateChange = mutateProtectedState { protectedState in
            guard !protectedState.sensorIdentity.isDeleted else {
                scanLogMessage = "MicroTech LinX scan ignored because CGM was deleted"
                return
            }

            if clearingConnectionError {
                protectedState.state.lastConnectionErrorDescription = nil
                protectedState.sensorIdentity.pendingReconnectRecoveryReason = nil
            }

            let manager = protectedState.bluetoothManager ?? bluetoothManagerFactory()
            manager.logHandler = { [weak self] message, type in
                self?.logDeviceCommunication(message, type: type.deviceLogEntryType)
            }
            protectedState.bluetoothManager = manager

            if let sensorSerial = currentState.sensorSerial, !sensorSerial.isEmpty,
               let activeSensor = protectedState.sensorIdentity.activeSensor
            {
                manager.delegate = activeSensor
                scanLogMessage = "MicroTech LinX scan using active sensor serial \(sensorSerial)"
            } else if let sensorSerial = currentState.sensorSerial, !sensorSerial.isEmpty {
                let session = MicroTechAidexSession(
                    remoteIdentifier: currentState.remoteIdentifier ?? UUID(),
                    deviceName: currentState.deviceName ?? "LinX-\(sensorSerial)",
                    sensorSerial: sensorSerial
                )
                let sensor = MicroTechSensor(
                    session: session,
                    peripheralSession: MicroTechPendingPeripheralSession(session: session)
                )
                sensor.delegate = self
                manager.delegate = sensor
                protectedState.sensorIdentity.activeSensor = sensor
                protectedState.sensorIdentity.activeIdentifier = ObjectIdentifier(sensor)
                scanLogMessage = "MicroTech LinX scan using saved sensor serial \(sensorSerial)"
            } else {
                manager.delegate = self
                scanLogMessage = "MicroTech LinX nearby scan started without saved sensor"
            }

            bluetoothManager = manager
            shouldRefreshConnectedPeripheral = manager.isConnected
            shouldStartScan = !(manager.isScanning || manager.isConnected)
        }
        notifyStateDidChange(from: stateChange.oldState, to: stateChange.newState)

        guard let bluetoothManager else {
            if let scanLogMessage {
                logDeviceCommunication(scanLogMessage, type: .connection)
            }
            return false
        }

        if shouldStartScan {
            bluetoothManager.scan(remoteIdentifier: currentState.remoteIdentifier)
            if let scanLogMessage {
                logDeviceCommunication("\(scanLogMessage), remoteIdentifier \(String(describing: currentState.remoteIdentifier))", type: .connection)
            }
        } else if shouldRefreshConnectedPeripheral {
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
            bluetoothManagerToDisconnect = protectedState.bluetoothManager
            if let activeIdentifier = protectedState.sensorIdentity.activeIdentifier {
                protectedState.sensorIdentity.retiredIdentifiers.insert(activeIdentifier)
            }
            protectedState.sensorIdentity.activeSensor = nil
            protectedState.sensorIdentity.activeIdentifier = nil
            protectedState.sensorIdentity.isDeleted = true
            protectedState.bluetoothManager = nil

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
        bluetoothManagerToDisconnect?.disconnect()
        bluetoothManagerToDisconnect?.forgetPeripheral()
        sensorToStop?.stop()
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

    func recordBluetoothFailure(_ error: Error) {
        var shouldRetrySavedSensorScan = false
        var shouldRestartForNearbySerialScan = false
        var bluetoothManagerToRestart: MicroTechBluetoothManaging?
        var fallbackFailureCount = 0
        let stateChange = mutateProtectedState { state in
            state.state.lastConnectionErrorDescription = "Bluetooth failed: \(String(describing: error))"
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
                    bluetoothManagerToRestart = state.bluetoothManager
                    shouldRestartForNearbySerialScan = true
                    return
                }
            }

            if case .scanTimeout = bluetoothError {
                shouldRetrySavedSensorScan = true
            }
        }
        notifyStateDidChange(from: stateChange.oldState, to: stateChange.newState)
        logDeviceCommunication("MicroTech LinX Bluetooth failed: \(String(describing: error))", type: .error)
        if shouldRestartForNearbySerialScan {
            logDeviceCommunication("MicroTech LinX clearing saved Bluetooth identifier after \(fallbackFailureCount) failures and scanning by sensor serial", type: .connection)
            bluetoothManagerToRestart?.disconnect()
            bluetoothRetryScheduler { [weak self] in
                self?.scanForSensor(clearingConnectionError: false)
            }
        } else if shouldRetrySavedSensorScan {
            logDeviceCommunication("MicroTech LinX retrying saved sensor scan after Bluetooth scan timeout", type: .connection)
            bluetoothRetryScheduler { [weak self] in
                self?.scanForSensor(clearingConnectionError: false)
            }
        }
        notifyDelegateOfReadingResult(.error(error))
    }

    func shouldConnectToMicroTechDevice(deviceName: String, identifier: UUID) -> Bool {
        let currentState = state
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

    private func isCurrentSensor(_ sensor: MicroTechSensor, in state: MicroTechSensorIdentityState) -> Bool {
        let identifier = ObjectIdentifier(sensor)
        return !state.isDeleted && state.activeIdentifier == identifier && !state.retiredIdentifiers.contains(identifier)
    }

    private func acceptSensorConnection(
        _ sensor: MicroTechSensor,
        session: MicroTechAidexSession,
        in state: inout MicroTechCGMManagerProtectedState
    ) -> Bool {
        let identifier = ObjectIdentifier(sensor)
        guard !state.sensorIdentity.isDeleted,
              !state.sensorIdentity.retiredIdentifiers.contains(identifier)
        else {
            return false
        }

        if let activeIdentifier = state.sensorIdentity.activeIdentifier, activeIdentifier != identifier {
            state.sensorIdentity.retiredIdentifiers.insert(activeIdentifier)
            state.sensorIdentity.resetHistoryTracking()
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
        state.sensorIdentity.activeIdentifier = identifier
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
        delegate.notify { delegate in
            delegate?.deviceManager(self, logEventForDeviceIdentifier: self.state.sensorSerial, type: type, message: message, completion: nil)
        }
    }

    private func resumeSavedSensorScanIfNeeded(reason: String) {
        var shouldScan = false
        lockedManagerState.mutate { state in
            guard !state.sensorIdentity.isDeleted,
                  state.state.sensorSerial?.isEmpty == false,
                  state.bluetoothManager?.isScanning != true,
                  state.bluetoothManager?.isConnected != true
            else {
                return
            }

            state.sensorIdentity.pendingReconnectRecoveryReason = reason
            shouldScan = true
        }

        guard shouldScan else {
            return
        }

        logDeviceCommunication("MicroTech LinX resume scan after \(reason)", type: .connection)
        scanForSensor(clearingConnectionError: false)
    }

    private func scheduleResumeSavedSensorScanIfNeeded(reason: String) {
        bluetoothRetryScheduler { [weak self] in
            self?.resumeSavedSensorScanIfNeeded(reason: reason)
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
        var bluetoothManager: MicroTechBluetoothManaging?
        var disconnectReason = "stale reading"
        let now = dateProvider()
        let shouldDisconnect = readProtectedState { state in
            guard state.state.sensorSerial?.isEmpty == false,
                  let manager = state.bluetoothManager,
                  manager.isConnected else
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

            bluetoothManager = manager
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
            deviceName.localizedCaseInsensitiveContains("AiDEX")
        else {
            return nil
        }

        let serial = sensorSerial(from: deviceName).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !serial.isEmpty, serial != deviceName else {
            return nil
        }
        return serial
    }

    private static func failedRemoteIdentifier(from error: MicroTechBluetoothManagerError) -> UUID? {
        switch error {
        case .connectTimeout(let identifier):
            return identifier
        case .connectFailed(let identifier, _):
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

    private static func hexPrefix(_ data: Data) -> String {
        Data(data.prefix(32)).microTechHexadecimalString
    }

    private static let glucoseUnit = HKUnit
        .gramUnit(with: .milli)
        .unitDivided(by: .literUnit(with: .deci))

    private static let linxAidexWarmupMinutes = 60
    private static let historyCaughtUpDistance = 2
    private static let historyRetrySampleDistance = 5
    private static let staleReadingReconnectInterval: TimeInterval = 15 * 60
    private static let consecutiveSensorErrorReconnectThreshold = 3
    private static let savedIdentifierFallbackFailureThreshold = 2
    private static let maxHistoryRejectionDetailsPerReason = 3
    private static let sampleIndexModulus = 65536
    private static let sampleIndexMask = 0xffff
    private static let halfSampleIndexRange = sampleIndexModulus / 2

    func connectDiscoveredSensor(peripheralSession: MicroTechPeripheralSession) {
        guard let sensorSerial = Self.advertisedSensorSerial(from: peripheralSession.deviceName) else {
            logDeviceCommunication("MicroTech LinX rejected discovered device \(peripheralSession.deviceName) because no sensor serial could be read", type: .connection)
            peripheralSession.disconnect()
            return
        }

        logDeviceCommunication("MicroTech LinX discovered device \(peripheralSession.deviceName), identifier \(peripheralSession.deviceIdentifier), sensor serial \(sensorSerial)", type: .connection)

        let session = MicroTechAidexSession(
            remoteIdentifier: peripheralSession.deviceIdentifier,
            deviceName: peripheralSession.deviceName,
            sensorSerial: sensorSerial
        )
        let sensor = MicroTechSensor(session: session, peripheralSession: peripheralSession)
        sensor.delegate = self

        var shouldStartSensor = false
        let stateChange = mutateProtectedState { protectedState in
            guard !protectedState.sensorIdentity.isDeleted else {
                return
            }

            let isNewSensor = protectedState.state.sensorSerial != sensorSerial
            if let activeIdentifier = protectedState.sensorIdentity.activeIdentifier {
                protectedState.sensorIdentity.retiredIdentifiers.insert(activeIdentifier)
            }
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
            protectedState.sensorIdentity.activeSensor = sensor
            protectedState.sensorIdentity.activeIdentifier = ObjectIdentifier(sensor)
            protectedState.sensorIdentity.activeSensorConnectedAt = self.dateProvider()
            protectedState.sensorIdentity.staleConnectionWatchdogIdentifier = UUID()
            protectedState.sensorIdentity.consecutiveSensorErrorCount = 0
            protectedState.sensorIdentity.savedIdentifierFailureCount = 0
            protectedState.state.remoteIdentifier = session.remoteIdentifier
            protectedState.state.deviceName = session.deviceName
            protectedState.state.sensorSerial = session.sensorSerial
            protectedState.state.lastConnectionErrorDescription = nil
            protectedState.bluetoothManager?.delegate = sensor
        }
        notifyStateDidChange(from: stateChange.oldState, to: stateChange.newState)

        guard shouldStartSensor else {
            logDeviceCommunication("MicroTech LinX discovered device ignored because CGM was deleted", type: .connection)
            peripheralSession.disconnect()
            return
        }

        DispatchQueue.global(qos: .utility).async {
            do {
                try sensor.start()
            } catch {
                self.logDeviceCommunication("MicroTech LinX sensor start failed: \(String(describing: error))", type: .error)
            }
        }
    }
}

extension MicroTechCGMManager: MicroTechBluetoothManagerDelegate {
    public func microTechBluetoothManager(_ manager: MicroTechBluetoothManager, shouldConnectToDeviceName deviceName: String, identifier: UUID) -> Bool {
        shouldConnectToMicroTechDevice(deviceName: deviceName, identifier: identifier)
    }

    public func microTechBluetoothManager(_ manager: MicroTechBluetoothManager, didReady peripheralSession: MicroTechPeripheralSession) {
        connectDiscoveredSensor(peripheralSession: peripheralSession)
    }

    public func microTechBluetoothManager(_ manager: MicroTechBluetoothManager, didReceive value: Data, for characteristic: CBUUID, session: MicroTechPeripheralSession) {
    }

    public func microTechBluetoothManager(_ manager: MicroTechBluetoothManager, didDisconnect session: MicroTechPeripheralSession) {
    }

    public func microTechBluetoothManager(_ manager: MicroTechBluetoothManager, didFailWith error: Error) {
        recordBluetoothFailure(error)
    }
}

extension MicroTechCGMManager: MicroTechSensorDelegate {
    public func microTechSensorDidConnect(_ sensor: MicroTechSensor, session: MicroTechAidexSession) {
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
        var shouldNotify = false
        lockedManagerState.mutate { state in
            shouldNotify = isCurrentSensor(sensor, in: state.sensorIdentity)
            guard shouldNotify else {
                return
            }

            state.sensorIdentity.activeSensorConnectedAt = nil
            state.sensorIdentity.staleConnectionWatchdogIdentifier = UUID()
        }

        guard shouldNotify else {
            return
        }

        delegate.notify { delegate in
            delegate?.cgmManager(self, didUpdate: self.cgmManagerStatus)
        }
        scheduleResumeSavedSensorScanIfNeeded(reason: "sensor disconnect")
    }

    public func microTechSensor(_ sensor: MicroTechSensor, didRead reading: MicroTechGlucoseReading) {
        var result: CGMReadingResult?
        var sample: NewGlucoseSample?
        var logMessage: String?
        var historyRequest: MicroTechHistoryRequest?
        let filterStartDate = startDateToFilterNewData()
        let stateChange = mutateProtectedState { state in
            guard isCurrentSensor(sensor, in: state.sensorIdentity) else {
                logMessage = "current ignored from inactive sensor serial=\(reading.sensorSerial) sample=\(reading.sampleNumber)"
                return
            }

            guard reading.isValidForTherapy else {
                result = .noData
                logMessage = "current rejected serial=\(reading.sensorSerial) sample=\(reading.sampleNumber) value=\(reading.glucoseMgdl) quality=\(reading.quality) reason=notTherapyValid"
                return
            }

            if let filterStartDate, reading.receivedAt < filterStartDate {
                result = .noData
                logMessage = "current rejected serial=\(reading.sensorSerial) sample=\(reading.sampleNumber) value=\(reading.glucoseMgdl) at=\(reading.receivedAt) startDate=\(filterStartDate) reason=beforeStartDate"
                return
            }

            if state.state.sensorSerial == reading.sensorSerial,
               let latestSampleNumber = state.state.latestSampleNumber,
               Self.isSampleNumber(reading.sampleNumber, notNewerThan: latestSampleNumber)
            {
                result = .noData
                logMessage = "current rejected serial=\(reading.sensorSerial) sample=\(reading.sampleNumber) latest=\(latestSampleNumber) reason=duplicateOrOld"
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
                logMessage = "current accepted serial=\(reading.sensorSerial) sample=\(reading.sampleNumber) value=\(reading.glucoseMgdl) packetType=\(Self.packetTypeDescription(reading.rawBytes)) rawPrefix=\(Self.hexPrefix(reading.rawBytes)) recoveredAfterReconnect reason=\(recoveryReason) at=\(reading.receivedAt)"
            } else {
                logMessage = "current accepted serial=\(reading.sensorSerial) sample=\(reading.sampleNumber) value=\(reading.glucoseMgdl) packetType=\(Self.packetTypeDescription(reading.rawBytes)) rawPrefix=\(Self.hexPrefix(reading.rawBytes)) at=\(reading.receivedAt)"
            }
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
        var samples: [NewGlucoseSample] = []
        var logMessage: String?
        var historyRequest: MicroTechHistoryRequest?
        let communicationDate = Date()
        let filterStartDate = startDateToFilterNewData()
        let stateChange = mutateProtectedState { state in
            guard isCurrentSensor(sensor, in: state.sensorIdentity),
                  let sensorSerial = state.state.sensorSerial
            else {
                logMessage = "history ignored from inactive sensor records=\(history.records.count)"
                return
            }

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
        let stateChange = mutateProtectedState { state in
            guard isCurrentSensor(sensor, in: state.sensorIdentity) else {
                return
            }
            state.state.activationTime = activationTime
            state.state.lastConnectionErrorDescription = nil
            state.sensorIdentity.consecutiveSensorErrorCount = 0
        }
        notifyStateDidChange(from: stateChange.oldState, to: stateChange.newState)
        logDeviceCommunication("MicroTech LinX sensor activation time \(activationTime)", type: .connection)
    }

    public func microTechSensor(_ sensor: MicroTechSensor, didIgnorePacketType packetType: UInt8, length: Int, hexPrefix: String) {
        let shouldLog = readProtectedState { state in
            isCurrentSensor(sensor, in: state.sensorIdentity)
        }

        guard shouldLog else {
            return
        }

        logDeviceCommunication(
            "MicroTech LinX ignored unsupported packet type \(String(format: "0x%02X", packetType)) len=\(length) rawPrefix=\(hexPrefix)",
            type: .receive
        )
    }

    public func microTechSensor(_ sensor: MicroTechSensor, didLog message: String, type: MicroTechSensorLogType) {
        let shouldLog = readProtectedState { state in
            isCurrentSensor(sensor, in: state.sensorIdentity) || state.sensorIdentity.activeSensor == nil
        }

        guard shouldLog else {
            return
        }

        logDeviceCommunication("MicroTech LinX \(message)", type: type.deviceLogEntryType)
    }

    public func microTechSensor(_ sensor: MicroTechSensor, didError error: Error) {
        if error is MicroTechBluetoothManagerError {
            let shouldHandle = readProtectedState { state in
                isCurrentSensor(sensor, in: state.sensorIdentity)
            }
            guard shouldHandle else {
                return
            }
            recordBluetoothFailure(error)
            return
        }

        var shouldNotify = false
        var bluetoothManager: MicroTechBluetoothManaging?
        var consecutiveErrorCount = 0
        let stateChange = mutateProtectedState { state in
            guard isCurrentSensor(sensor, in: state.sensorIdentity) else {
                return
            }

            shouldNotify = true
            state.state.lastConnectionErrorDescription = "Sensor error: \(String(describing: error))"
            state.sensorIdentity.consecutiveSensorErrorCount += 1
            consecutiveErrorCount = state.sensorIdentity.consecutiveSensorErrorCount
            if consecutiveErrorCount >= Self.consecutiveSensorErrorReconnectThreshold {
                bluetoothManager = state.bluetoothManager
                state.sensorIdentity.consecutiveSensorErrorCount = 0
            }
        }

        guard shouldNotify else {
            return
        }

        notifyStateDidChange(from: stateChange.oldState, to: stateChange.newState)
        logDeviceCommunication("MicroTech LinX sensor error: \(String(describing: error)) consecutive=\(consecutiveErrorCount)", type: .error)
        if let bluetoothManager {
            logDeviceCommunication("MicroTech LinX restarting connection after \(consecutiveErrorCount) consecutive sensor errors", type: .connection)
            bluetoothManager.disconnect()
            scheduleResumeSavedSensorScanIfNeeded(reason: "\(consecutiveErrorCount) consecutive sensor errors")
        }
        notifyDelegateOfReadingResult(.error(error))
    }
}

private extension MicroTechBluetoothLogType {
    var deviceLogEntryType: DeviceLogEntryType {
        switch self {
        case .connection:
            return .connection
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
    var bluetoothManager: MicroTechBluetoothManaging?
}

private struct MicroTechSensorIdentityState {
    var activeSensor: MicroTechSensor?
    var activeIdentifier: ObjectIdentifier?
    var retiredIdentifiers: Set<ObjectIdentifier> = []
    var emittedHistorySampleNumbers: Set<Int> = []
    var historyBackfillRequestedFrom: Int?
    var historyBackfillRequestedAtCurrentIndex: Int?
    var activeSensorConnectedAt: Date?
    var staleConnectionWatchdogIdentifier = UUID()
    var consecutiveSensorErrorCount = 0
    var savedIdentifierFailureCount = 0
    var pendingReconnectRecoveryReason: String?
    var isDeleted = false

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
