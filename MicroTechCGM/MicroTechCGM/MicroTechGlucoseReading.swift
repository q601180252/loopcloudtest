import Foundation
import HealthKit
import LoopKit

public struct MicroTechGlucoseReading: Equatable, GlucoseDisplayable {
    public let sensorSerial: String
    public let sampleNumber: Int
    public let glucoseMgdl: Int
    public let trend: Int
    public let receivedAt: Date
    public let status: Int
    public let quality: Int
    public let rawBytes: Data

    public init(current: MicroTechAidexCurrentPacket, sensorSerial: String, receivedAt: Date) {
        self.sensorSerial = sensorSerial
        self.sampleNumber = current.timeOffset
        self.glucoseMgdl = current.glucose
        self.trend = current.trend + 1
        self.receivedAt = receivedAt
        self.status = current.status
        self.quality = current.quality
        self.rawBytes = current.rawBytes
    }

    public var syncIdentifier: String {
        "\(sensorSerial)-\(sampleNumber)"
    }

    public var isValidForTherapy: Bool {
        sampleNumber > 0 && glucoseMgdl >= 40 && glucoseMgdl <= 400 && quality == 0
    }

    public var glucoseQuantity: HKQuantity? {
        HKQuantity(unit: Self.glucoseUnit, doubleValue: Double(glucoseMgdl))
    }

    public var isStateValid: Bool {
        isValidForTherapy
    }

    public var trendRate: HKQuantity? {
        HKQuantity(unit: Self.glucoseRateUnit, doubleValue: Double(trend))
    }

    public var trendType: GlucoseTrend? {
        switch trend {
        case let value where value <= -3:
            return .downDownDown
        case -2:
            return .downDown
        case -1:
            return .down
        case 0:
            return .flat
        case 1:
            return .up
        case 2:
            return .upUp
        case let value where value >= 3:
            return .upUpUp
        default:
            return nil
        }
    }

    public var glucoseRangeCategory: GlucoseRangeCategory? {
        if glucoseMgdl < 40 {
            return .belowRange
        }
        if glucoseMgdl > 400 {
            return .aboveRange
        }
        return nil
    }

    public var isLocal: Bool {
        true
    }

    private static let glucoseUnit = HKUnit
        .gramUnit(with: .milli)
        .unitDivided(by: .literUnit(with: .deci))

    private static let glucoseRateUnit = glucoseUnit.unitDivided(by: .minute())
}
