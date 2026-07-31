import Foundation
import LoopKit
import LoopKitUI
import MicroTechCGM

final class MicroTechSettingsViewModel: ObservableObject {
    @Published private(set) var deviceName: String?
    @Published private(set) var sensorSerial: String?
    @Published private(set) var lastReadingDate: Date?
    @Published private(set) var lastGlucoseString: String
    @Published private(set) var isScanning: Bool
    @Published private(set) var scanButtonTitle: String
    @Published private(set) var dataModeDescription: String
    @Published private(set) var connectionErrorDescription: String?
    @Published var uploadReadings: Bool {
        didSet {
            if cgmManager.uploadReadings != uploadReadings {
                cgmManager.uploadReadings = uploadReadings
            }
        }
    }

    let dateFormatter: DateFormatter

    private let cgmManager: MicroTechCGMManager
    private let displayGlucosePreference: DisplayGlucosePreference

    init(cgmManager: MicroTechCGMManager, displayGlucosePreference: DisplayGlucosePreference) {
        self.cgmManager = cgmManager
        self.displayGlucosePreference = displayGlucosePreference
        self.dateFormatter = DateFormatter()
        self.dateFormatter.dateStyle = .short
        self.dateFormatter.timeStyle = .short
        self.lastGlucoseString = LocalizedString("--", comment: "No glucose value placeholder")
        self.isScanning = cgmManager.isScanning
        self.scanButtonTitle = LocalizedString("Scan for Sensor", comment: "MicroTech settings scan button label")
        self.dataModeDescription = Self.dataModeDescription(for: cgmManager.state.connectionMode)
        self.uploadReadings = cgmManager.state.uploadReadings

        refresh()
        cgmManager.addStatusObserver(self, queue: .main)
    }

    deinit {
        cgmManager.removeStatusObserver(self)
    }

    func refresh() {
        let state = cgmManager.state
        deviceName = state.deviceName
        sensorSerial = state.sensorSerial
        lastReadingDate = state.lastReadingDate
        uploadReadings = state.uploadReadings
        isScanning = cgmManager.isScanning
        scanButtonTitle = LocalizedString("Scan for Sensor", comment: "MicroTech settings scan button label")
        dataModeDescription = Self.dataModeDescription(for: state.connectionMode)
        connectionErrorDescription = state.lastConnectionErrorDescription
        lastGlucoseString = Self.glucoseString(
            from: state.latestReading,
            connectionMode: state.connectionMode,
            displayGlucosePreference: displayGlucosePreference
        )
    }

    func scanForSensor() {
        cgmManager.scanForSensor()
        refresh()
    }

    private static func glucoseString(
        from reading: MicroTechGlucoseReading?,
        connectionMode: MicroTechCGMConnectionMode,
        displayGlucosePreference: DisplayGlucosePreference
    ) -> String {
        guard let reading,
              (reading.isValidForTherapy || (connectionMode == .broadcast && (40...400).contains(reading.glucoseMgdl))),
              let quantity = reading.glucoseQuantity
        else {
            return LocalizedString("--", comment: "No glucose value placeholder")
        }

        switch reading.glucoseRangeCategory {
        case .some(.belowRange):
            return LocalizedString("LOW", comment: "String displayed instead of a glucose value below the CGM range")
        case .some(.aboveRange):
            return LocalizedString("HIGH", comment: "String displayed instead of a glucose value above the CGM range")
        default:
            return displayGlucosePreference.formatter.string(from: quantity) ?? LocalizedString("--", comment: "No glucose value placeholder")
        }
    }

    private static func dataModeDescription(for connectionMode: MicroTechCGMConnectionMode) -> String {
        switch connectionMode {
        case .direct:
            return LocalizedString("Direct Connection", comment: "MicroTech settings direct connection data mode")
        case .broadcast:
            return LocalizedString("Broadcast Data", comment: "MicroTech settings broadcast data mode")
        }
    }
}

extension MicroTechSettingsViewModel: CGMManagerStatusObserver {
    func cgmManager(_ manager: CGMManager, didUpdate status: CGMManagerStatus) {
        refresh()
    }
}
