import Foundation
import LoopKit

public struct MicroTechCGMManagerState: RawRepresentable, Equatable {
    public typealias RawValue = CGMManager.RawStateValue

    public var remoteIdentifier: UUID?
    public var deviceName: String?
    public var sensorSerial: String?
    public var activationTime: Date?
    public var lastReadingDate: Date?
    public var latestReading: MicroTechGlucoseReading?
    public var latestSampleNumber: Int?
    public var uploadReadings: Bool

    public init() {
        uploadReadings = false
    }

    public init(rawValue: RawValue) {
        if let identifier = rawValue["remoteIdentifier"] as? UUID {
            remoteIdentifier = identifier
        } else if let identifier = rawValue["remoteIdentifier"] as? String {
            remoteIdentifier = UUID(uuidString: identifier)
        }

        deviceName = rawValue["deviceName"] as? String
        sensorSerial = rawValue["sensorSerial"] as? String
        activationTime = rawValue["activationTime"] as? Date
        lastReadingDate = rawValue["lastReadingDate"] as? Date
        latestSampleNumber = rawValue["latestSampleNumber"] as? Int
        uploadReadings = rawValue["uploadReadings"] as? Bool ?? false
    }

    public var rawValue: RawValue {
        var rawValue: RawValue = [:]
        rawValue["remoteIdentifier"] = remoteIdentifier?.uuidString
        rawValue["deviceName"] = deviceName
        rawValue["sensorSerial"] = sensorSerial
        rawValue["activationTime"] = activationTime
        rawValue["lastReadingDate"] = lastReadingDate
        rawValue["latestSampleNumber"] = latestSampleNumber
        rawValue["uploadReadings"] = uploadReadings
        return rawValue
    }
}
