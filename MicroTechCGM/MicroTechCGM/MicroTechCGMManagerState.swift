import Foundation
import LoopKit

public enum MicroTechCGMConnectionMode: String, Codable, Equatable {
    case direct
    case broadcast
}

public struct MicroTechCGMManagerState: RawRepresentable, Equatable {
    public typealias RawValue = CGMManager.RawStateValue

    public var remoteIdentifier: UUID?
    public var deviceName: String?
    public var sensorSerial: String?
    public var activationTime: Date?
    public var lastReadingDate: Date?
    public var latestReading: MicroTechGlucoseReading?
    public var latestSampleNumber: Int?
    public var hasConnectedSensorSession: Bool
    public var uploadReadings: Bool
    public var connectionMode: MicroTechCGMConnectionMode
    public var lastConnectionErrorDescription: String?

    public init() {
        hasConnectedSensorSession = false
        uploadReadings = false
        connectionMode = .direct
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
        latestReading = Self.restoreLatestReading(from: rawValue["latestReading"])
        hasConnectedSensorSession = rawValue["hasConnectedSensorSession"] as? Bool ?? (sensorSerial?.isEmpty == false)
        uploadReadings = rawValue["uploadReadings"] as? Bool ?? false
        connectionMode = (rawValue["connectionMode"] as? String).flatMap(MicroTechCGMConnectionMode.init(rawValue:)) ?? .direct
        lastConnectionErrorDescription = rawValue["lastConnectionErrorDescription"] as? String
    }

    public var rawValue: RawValue {
        var rawValue: RawValue = [:]
        rawValue["remoteIdentifier"] = remoteIdentifier?.uuidString
        rawValue["deviceName"] = deviceName
        rawValue["sensorSerial"] = sensorSerial
        rawValue["activationTime"] = activationTime
        rawValue["lastReadingDate"] = lastReadingDate
        rawValue["latestSampleNumber"] = latestSampleNumber
        rawValue["latestReading"] = latestReading.map(Self.rawValue(for:))
        rawValue["hasConnectedSensorSession"] = hasConnectedSensorSession
        rawValue["uploadReadings"] = uploadReadings
        rawValue["connectionMode"] = connectionMode.rawValue
        rawValue["lastConnectionErrorDescription"] = lastConnectionErrorDescription
        return rawValue
    }

    private static func rawValue(for reading: MicroTechGlucoseReading) -> RawValue {
        [
            "sensorSerial": reading.sensorSerial,
            "sampleNumber": reading.sampleNumber,
            "glucoseMgdl": reading.glucoseMgdl,
            "trend": reading.trend,
            "receivedAt": reading.receivedAt,
            "status": reading.status,
            "quality": reading.quality,
            "rawBytes": reading.rawBytes,
        ]
    }

    private static func restoreLatestReading(from value: Any?) -> MicroTechGlucoseReading? {
        guard let rawValue = value as? RawValue,
              let sensorSerial = rawValue["sensorSerial"] as? String,
              let sampleNumber = rawValue["sampleNumber"] as? Int,
              let glucoseMgdl = rawValue["glucoseMgdl"] as? Int,
              let trend = rawValue["trend"] as? Int,
              let receivedAt = rawValue["receivedAt"] as? Date,
              let status = rawValue["status"] as? Int,
              let quality = rawValue["quality"] as? Int,
              let rawBytes = rawValue["rawBytes"] as? Data else
        {
            return nil
        }

        return MicroTechGlucoseReading(
            sensorSerial: sensorSerial,
            sampleNumber: sampleNumber,
            glucoseMgdl: glucoseMgdl,
            trend: trend,
            receivedAt: receivedAt,
            status: status,
            quality: quality,
            rawBytes: rawBytes
        )
    }
}
