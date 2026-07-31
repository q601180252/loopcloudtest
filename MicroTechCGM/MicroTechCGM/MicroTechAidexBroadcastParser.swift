import Foundation

public struct MicroTechAidexBroadcastRecord: Equatable {
    public let timeOffset: UInt16
    public let glucose: Int
    public let reserved: UInt8
    public let quality: UInt8

    public init(timeOffset: UInt16, glucose: Int, reserved: UInt8, quality: UInt8) {
        self.timeOffset = timeOffset
        self.glucose = glucose
        self.reserved = reserved
        self.quality = quality
    }
}

public struct MicroTechAidexBroadcastReading: Equatable {
    public let timeOffset: UInt16
    public let status: UInt8
    public let calibrationTemperature: UInt8
    public let trend: Int
    public let records: [MicroTechAidexBroadcastRecord]
    public let rawManufacturerPayload: Data

    public var latestRecord: MicroTechAidexBroadcastRecord? {
        records.first
    }
}

public enum MicroTechAidexBroadcastParserError: Error, Equatable {
    case missingManufacturerData
    case wrongCompanyIdentifier
    case payloadTooShort
    case noRecords
    case sensorNotReady(UInt16)
    case invalidGlucose(Int)
}

public enum MicroTechAidexBroadcastParser {
    private static let companyIdentifier = [UInt8(0x59), 0x00]
    private static let headerLength = 5
    private static let recordLength = 3
    private static let maximumRecordCount = 3
    private static let warmupMinutes: UInt16 = 7

    public static func parseAdvertisementData(_ advertisementData: [String: Any]) throws -> MicroTechAidexBroadcastReading {
        guard let manufacturerData = advertisementData["kCBAdvDataManufacturerData"] as? Data else {
            throw MicroTechAidexBroadcastParserError.missingManufacturerData
        }

        return try parseManufacturerData(manufacturerData)
    }

    public static func parseAdvertisingPayload(_ data: Data) throws -> MicroTechAidexBroadcastReading {
        let bytes = [UInt8](data)
        var index = 0

        while index < bytes.count {
            let length = Int(bytes[index])
            guard length > 0 else {
                break
            }

            let fieldEnd = index + length + 1
            guard fieldEnd <= bytes.count else {
                break
            }

            if bytes[index + 1] == 0xFF {
                let manufacturerData = Data(bytes[(index + 2)..<fieldEnd])
                return try parseManufacturerData(manufacturerData)
            }

            index = fieldEnd
        }

        throw MicroTechAidexBroadcastParserError.missingManufacturerData
    }

    public static func parseManufacturerPayload(_ data: Data) throws -> MicroTechAidexBroadcastReading {
        let bytes = [UInt8](data)
        guard bytes.count >= headerLength else {
            throw MicroTechAidexBroadcastParserError.payloadTooShort
        }

        let timeOffset = UInt16(bytes[0]) | UInt16(bytes[1]) << 8
        guard timeOffset >= warmupMinutes else {
            throw MicroTechAidexBroadcastParserError.sensorNotReady(timeOffset)
        }
        let recordByteCount = bytes.count - headerLength
        let recordCount = min(recordByteCount / recordLength, maximumRecordCount)
        guard recordCount > 0 else {
            throw MicroTechAidexBroadcastParserError.noRecords
        }

        var records: [MicroTechAidexBroadcastRecord] = []
        for index in 0..<recordCount {
            let recordStart = headerLength + index * recordLength
            let glucose = Int(bytes[recordStart])
            if glucose == 0xFF {
                guard index > 0 else {
                    throw MicroTechAidexBroadcastParserError.invalidGlucose(glucose)
                }
                break
            }
            guard (40...400).contains(glucose) else {
                throw MicroTechAidexBroadcastParserError.invalidGlucose(glucose)
            }

            records.append(MicroTechAidexBroadcastRecord(
                timeOffset: timeOffset &- UInt16(index),
                glucose: glucose,
                reserved: bytes[recordStart + 1],
                quality: bytes[recordStart + 2]
            ))
        }

        return MicroTechAidexBroadcastReading(
            timeOffset: timeOffset,
            status: bytes[2],
            calibrationTemperature: bytes[3],
            trend: Int(Int8(bitPattern: bytes[4])),
            records: records,
            rawManufacturerPayload: data
        )
    }

    private static func parseManufacturerData(_ data: Data) throws -> MicroTechAidexBroadcastReading {
        guard data.count >= companyIdentifier.count else {
            throw MicroTechAidexBroadcastParserError.wrongCompanyIdentifier
        }
        guard data.starts(with: companyIdentifier) else {
            throw MicroTechAidexBroadcastParserError.wrongCompanyIdentifier
        }

        return try parseManufacturerPayload(data.dropFirst(companyIdentifier.count))
    }
}
