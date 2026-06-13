import Foundation
import LoopKitUI
import MicroTechCGM

final class MicroTechSettingsViewModel: ObservableObject {
    @Published private(set) var deviceName: String?
    @Published private(set) var sensorSerial: String?
    @Published private(set) var lastReadingDate: Date?
    @Published private(set) var lastGlucoseString: String
    @Published var uploadReadings: Bool

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
        self.uploadReadings = cgmManager.state.uploadReadings

        refresh()
    }

    func refresh() {
        let state = cgmManager.state
        deviceName = state.deviceName
        sensorSerial = state.sensorSerial
        lastReadingDate = state.lastReadingDate
        uploadReadings = state.uploadReadings
        lastGlucoseString = Self.glucoseString(from: state.latestReading, displayGlucosePreference: displayGlucosePreference)
    }

    private static func glucoseString(from reading: MicroTechGlucoseReading?, displayGlucosePreference: DisplayGlucosePreference) -> String {
        guard let reading = reading, reading.isValidForTherapy, let quantity = reading.glucoseQuantity else {
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
}
