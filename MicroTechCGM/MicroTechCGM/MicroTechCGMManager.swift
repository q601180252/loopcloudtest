import CoreBluetooth
import Foundation
import HealthKit
import LoopKit

public final class MicroTechCGMManager: CGMManager {
    private let lockedManagerState: Locked<MicroTechCGMManagerProtectedState>
    private let delegate = WeakSynchronizedDelegate<CGMManagerDelegate>()
    private let bluetoothManagerFactory: () -> MicroTechBluetoothManaging

    public static let pluginIdentifier = "MicroTechLinXCGMManager"

    public let localizedTitle = "MicroTech LinX"
    public let isOnboarded = true
    public let providesBLEHeartbeat = true

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
            hasValidSensorSession: state.sensorSerial != nil,
            lastCommunicationDate: state.lastReadingDate,
            device: device(for: state)
        )
    }

    public init() {
        bluetoothManagerFactory = { MicroTechBluetoothManager() }
        lockedManagerState = Locked(MicroTechCGMManagerProtectedState(state: MicroTechCGMManagerState()))
    }

    init(
        state: MicroTechCGMManagerState,
        bluetoothManagerFactory: @escaping () -> MicroTechBluetoothManaging = { MicroTechBluetoothManager() }
    ) {
        self.bluetoothManagerFactory = bluetoothManagerFactory
        lockedManagerState = Locked(MicroTechCGMManagerProtectedState(state: state))
    }

    public required init?(rawState: RawStateValue) {
        bluetoothManagerFactory = { MicroTechBluetoothManager() }
        lockedManagerState = Locked(MicroTechCGMManagerProtectedState(state: MicroTechCGMManagerState(rawValue: rawState)))
    }

    public var rawState: RawStateValue {
        state.rawValue
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
            "uploadReadings: \(String(describing: state.uploadReadings))",
        ]
        return lines.joined(separator: "\n")
    }

    public func fetchNewDataIfNeeded(_ completion: @escaping (CGMReadingResult) -> Void) {
        scanForSensor()
        completion(.noData)
    }

    @discardableResult
    public func scanForSensor() -> Bool {
        let currentState = state
        guard let sensorSerial = currentState.sensorSerial, !sensorSerial.isEmpty else {
            return false
        }

        var bluetoothManager: MicroTechBluetoothManaging?
        var shouldStartScan = false

        _ = mutateProtectedState { protectedState in
            guard !protectedState.sensorIdentity.isDeleted else {
                return
            }

            let manager = protectedState.bluetoothManager ?? bluetoothManagerFactory()
            protectedState.bluetoothManager = manager

            if let activeSensor = protectedState.sensorIdentity.activeSensor {
                manager.delegate = activeSensor
            } else {
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
            }

            bluetoothManager = manager
            shouldStartScan = !(manager.isScanning || manager.isConnected)
        }

        guard let bluetoothManager else {
            return false
        }

        if shouldStartScan {
            bluetoothManager.scan(remoteIdentifier: currentState.remoteIdentifier)
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
        }
        notifyStateDidChange(from: stateChange.oldState, to: stateChange.newState)
        bluetoothManagerToDisconnect?.disconnect()
        bluetoothManagerToDisconnect?.forgetPeripheral()
        sensorToStop?.stop()
        notifyDelegateOfDeletion(completion: completion)
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
               reading.sampleNumber <= latestSampleNumber
            {
                return
            }

            state.sensorSerial = reading.sensorSerial
            state.lastReadingDate = reading.receivedAt
            state.latestReading = reading
            state.latestSampleNumber = reading.sampleNumber
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
        }

        if let sensorSerial = state.state.sensorSerial, sensorSerial != session.sensorSerial {
            state.state.activationTime = nil
            state.state.lastReadingDate = nil
            state.state.latestReading = nil
            state.state.latestSampleNumber = nil
        }

        state.sensorIdentity.activeSensor = sensor
        state.sensorIdentity.activeIdentifier = identifier
        state.state.remoteIdentifier = session.remoteIdentifier
        state.state.deviceName = session.deviceName
        state.state.sensorSerial = session.sensorSerial
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

        delegate.notify { delegate in
            delegate?.cgmManagerDidUpdateState(self)
            delegate?.cgmManager(self, didUpdate: self.cgmManagerStatus)
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
}

extension MicroTechCGMManager: MicroTechSensorDelegate {
    public func microTechSensorDidConnect(_ sensor: MicroTechSensor, session: MicroTechAidexSession) {
        var didAccept = false
        let stateChange = mutateProtectedState { state in
            didAccept = acceptSensorConnection(sensor, session: session, in: &state)
        }

        guard didAccept else {
            return
        }

        notifyStateDidChange(from: stateChange.oldState, to: stateChange.newState)
    }

    public func microTechSensorDidDisconnect(_ sensor: MicroTechSensor) {
        let shouldNotify = readProtectedState { state in
            isCurrentSensor(sensor, in: state.sensorIdentity)
        }

        guard shouldNotify else {
            return
        }

        delegate.notify { delegate in
            delegate?.cgmManager(self, didUpdate: self.cgmManagerStatus)
        }
    }

    public func microTechSensor(_ sensor: MicroTechSensor, didRead reading: MicroTechGlucoseReading) {
        var result: CGMReadingResult?
        var sample: NewGlucoseSample?
        let stateChange = mutateProtectedState { state in
            guard isCurrentSensor(sensor, in: state.sensorIdentity) else {
                return
            }

            guard reading.isValidForTherapy else {
                result = .noData
                return
            }

            if state.state.sensorSerial == reading.sensorSerial,
               let latestSampleNumber = state.state.latestSampleNumber,
               reading.sampleNumber <= latestSampleNumber
            {
                result = .noData
                return
            }

            state.state.sensorSerial = reading.sensorSerial
            state.state.lastReadingDate = reading.receivedAt
            state.state.latestReading = reading
            state.state.latestSampleNumber = reading.sampleNumber
            sample = makeSample(from: reading, state: state.state)
        }

        notifyStateDidChange(from: stateChange.oldState, to: stateChange.newState)

        if let sample {
            notifyDelegateOfReadingResult(.newData([sample]))
        } else if let result {
            notifyDelegateOfReadingResult(result)
        }
    }

    public func microTechSensor(_ sensor: MicroTechSensor, didReadHistory history: MicroTechAidexHistoryPacket) {
        let shouldNotify = readProtectedState { state in
            isCurrentSensor(sensor, in: state.sensorIdentity)
        }

        guard shouldNotify else {
            return
        }

        notifyDelegateOfReadingResult(.noData)
    }

    public func microTechSensor(_ sensor: MicroTechSensor, didError error: Error) {
        let shouldNotify = readProtectedState { state in
            isCurrentSensor(sensor, in: state.sensorIdentity)
        }

        guard shouldNotify else {
            return
        }

        notifyDelegateOfReadingResult(.error(error))
    }
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
    var isDeleted = false
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
