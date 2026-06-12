import Foundation

public enum MicroTechAidexParserError: Error, Equatable {
    case emptyPacket
    case invalidCRC
    case invalidPacket
    case unsupportedPacket(UInt8)
}

public enum MicroTechAidexPacket: Equatable {
    case current(MicroTechAidexCurrentPacket)
    case history(MicroTechAidexHistoryPacket)
    case startTime(MicroTechAidexStartTimePacket)
}

public struct MicroTechAidexCurrentPacket: Equatable {
    public let rawBytes: Data
    public let packetType: UInt8
    public let trend: Int
    public let timeOffset: Int
    public let glucoseRaw: Int
    public let glucose: Int
    public let quality: Int
    public let i1: Double
    public let i2: Double
    public let vc: Double
    public let status: Int
    public let byte14Flag: Int
}

public struct MicroTechAidexHistoryRecord: Equatable {
    public let timeOffset: Int
    public let glucose: Int
    public let rawValue: Int
}

public struct MicroTechAidexHistoryPacket: Equatable {
    public let rawBytes: Data
    public let startTimeOffset: Int
    public let records: [MicroTechAidexHistoryRecord]
}

public struct MicroTechAidexStartTimePacket: Equatable {
    public let rawBytes: Data
    public let startTimeByte: UInt8
    public let timestamp: Date?
}
