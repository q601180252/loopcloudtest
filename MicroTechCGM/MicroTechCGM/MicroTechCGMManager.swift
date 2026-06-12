import Foundation
import HealthKit
import LoopKit

public final class MicroTechCGMManager: CGMManager {
    private let lockedState: Locked<MicroTechCGMManagerState>
    private let lockedSensorIdentity: Locked<MicroTechSensorIdentityState>
    private let delegate = WeakSynchronizedDelegate<CGMManagerDelegate>()

    public static let pluginIdentifier = "MicroTechLinXCGMManager"

    public let localizedTitle = "MicroTech LinX"
    public let isOnboarded = true
    public let providesBLEHeartbeat = true

    public var state: MicroTechCGMManagerState {
        lockedState.value
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
        lockedState = Locked(MicroTechCGMManagerState())
        lockedSensorIdentity = Locked(MicroTechSensorIdentityState())
    }

    init(state: MicroTechCGMManagerState) {
        lockedState = Locked(state)
        lockedSensorIdentity = Locked(MicroTechSensorIdentityState())
    }

    public required init?(rawState: RawStateValue) {
        lockedState = Locked(MicroTechCGMManagerState(rawValue: rawState))
        lockedSensorIdentity = Locked(MicroTechSensorIdentityState())
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
        lockedSensorIdentity.mutate { state in
            sensorToStop = state.activeSensor
            if let activeIdentifier = state.activeIdentifier {
                state.retiredIdentifiers.insert(activeIdentifier)
            }
            state.activeSensor = nil
            state.activeIdentifier = nil
        }
        mutateState { state in
            state.remoteIdentifier = nil
            state.deviceName = nil
            state.sensorSerial = nil
            state.activationTime = nil
            state.lastReadingDate = nil
            state.latestReading = nil
            state.latestSampleNumber = nil
        }
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
        var oldValue: MicroTechCGMManagerState!
        let newValue = lockedState.mutate { state in
            oldValue = state
            mutation(&state)
        }

        notifyStateDidChange(from: oldValue, to: newValue)
        return newValue
    }

    private func notifyDelegateOfReadingResult(_ result: CGMReadingResult) {
        delegate.notify { delegate in
            delegate?.cgmManager(self, hasNew: result)
        }
    }

    private func isCurrentSensor(_ sensor: MicroTechSensor) -> Bool {
        let identifier = ObjectIdentifier(sensor)
        let state = lockedSensorIdentity.value
        return state.activeIdentifier == identifier && !state.retiredIdentifiers.contains(identifier)
    }

    private func acceptSensorConnection(_ sensor: MicroTechSensor) -> Bool {
        let identifier = ObjectIdentifier(sensor)
        var isAccepted = false
        lockedSensorIdentity.mutate { state in
            guard !state.retiredIdentifiers.contains(identifier) else {
                return
            }

            if let activeIdentifier = state.activeIdentifier, activeIdentifier != identifier {
                state.retiredIdentifiers.insert(activeIdentifier)
            }

            state.activeSensor = sensor
            state.activeIdentifier = identifier
            isAccepted = true
        }
        return isAccepted
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
        guard acceptSensorConnection(sensor), isCurrentSensor(sensor) else {
            return
        }

        mutateState { state in
            state.remoteIdentifier = session.remoteIdentifier
            state.deviceName = session.deviceName
            state.sensorSerial = session.sensorSerial
        }
    }

    public func microTechSensorDidDisconnect(_ sensor: MicroTechSensor) {
        guard isCurrentSensor(sensor) else {
            return
        }

        delegate.notify { delegate in
            delegate?.cgmManager(self, didUpdate: self.cgmManagerStatus)
        }
    }

    public func microTechSensor(_ sensor: MicroTechSensor, didRead reading: MicroTechGlucoseReading) {
        guard isCurrentSensor(sensor) else {
            return
        }

        guard let sample = accept(reading) else {
            notifyDelegateOfReadingResult(.noData)
            return
        }

        notifyDelegateOfReadingResult(.newData([sample]))
    }

    public func microTechSensor(_ sensor: MicroTechSensor, didReadHistory history: MicroTechAidexHistoryPacket) {
        guard isCurrentSensor(sensor) else {
            return
        }

        notifyDelegateOfReadingResult(.noData)
    }

    public func microTechSensor(_ sensor: MicroTechSensor, didError error: Error) {
        guard isCurrentSensor(sensor) else {
            return
        }

        notifyDelegateOfReadingResult(.error(error))
    }
}

private struct MicroTechSensorIdentityState {
    var activeSensor: MicroTechSensor?
    var activeIdentifier: ObjectIdentifier?
    var retiredIdentifiers: Set<ObjectIdentifier> = []
}
