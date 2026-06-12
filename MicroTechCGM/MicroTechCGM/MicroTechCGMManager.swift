import Foundation
import HealthKit
import LoopKit

public final class MicroTechCGMManager: CGMManager {
    private let lockedState: Locked<MicroTechCGMManagerState>
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
    }

    init(state: MicroTechCGMManagerState) {
        lockedState = Locked(state)
    }

    public required init?(rawState: RawStateValue) {
        lockedState = Locked(MicroTechCGMManagerState(rawValue: rawState))
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

        var oldValue: MicroTechCGMManagerState!
        var sample: NewGlucoseSample?
        let newValue = lockedState.mutate { state in
            oldValue = state

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

        notifyStateDidChange(from: oldValue, to: newValue)
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
