import Foundation
import HealthKit
import LoopKit

public final class MicroTechCGMManager: CGMManager {
    private let lockedManagerState: Locked<MicroTechCGMManagerProtectedState>
    private let delegate = WeakSynchronizedDelegate<CGMManagerDelegate>()

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

    public var shouldSyncToRemoteService: Bool {
        state.uploadReadings
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
        lockedManagerState = Locked(MicroTechCGMManagerProtectedState(state: MicroTechCGMManagerState()))
    }

    init(state: MicroTechCGMManagerState) {
        lockedManagerState = Locked(MicroTechCGMManagerProtectedState(state: state))
    }

    public required init?(rawState: RawStateValue) {
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
        completion(.noData)
    }

    public func delete(completion: @escaping () -> Void) {
        var sensorToStop: MicroTechSensor?
        let stateChange = mutateProtectedState { protectedState in
            sensorToStop = protectedState.sensorIdentity.activeSensor
            if let activeIdentifier = protectedState.sensorIdentity.activeIdentifier {
                protectedState.sensorIdentity.retiredIdentifiers.insert(activeIdentifier)
            }
            protectedState.sensorIdentity.activeSensor = nil
            protectedState.sensorIdentity.activeIdentifier = nil
            protectedState.sensorIdentity.isDeleted = true

            protectedState.state.remoteIdentifier = nil
            protectedState.state.deviceName = nil
            protectedState.state.sensorSerial = nil
            protectedState.state.activationTime = nil
            protectedState.state.lastReadingDate = nil
            protectedState.state.latestReading = nil
            protectedState.state.latestSampleNumber = nil
        }
        notifyStateDidChange(from: stateChange.oldState, to: stateChange.newState)
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
}

private struct MicroTechSensorIdentityState {
    var activeSensor: MicroTechSensor?
    var activeIdentifier: ObjectIdentifier?
    var retiredIdentifiers: Set<ObjectIdentifier> = []
    var isDeleted = false
}
