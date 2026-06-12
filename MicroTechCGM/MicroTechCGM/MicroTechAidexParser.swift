import Foundation

public enum MicroTechAidexParser {
    public static func parse(_ packet: Data) throws -> MicroTechAidexPacket {
        guard let packetType = packet.first else {
            throw MicroTechAidexParserError.emptyPacket
        }

        if packetType != 0x21 && !MicroTechAidexCrypto.hasValidTrailingCRC(packet) {
            throw MicroTechAidexParserError.invalidCRC
        }

        switch packetType {
        case 0x01:
            return .current(try parseCurrent(packet))
        case 0x21:
            return .startTime(parseStartTime(packet))
        case 0x23:
            return .history(try parseHistory(packet))
        default:
            throw MicroTechAidexParserError.unsupportedPacket(packetType)
        }
    }

    private static func parseCurrent(_ data: Data) throws -> MicroTechAidexCurrentPacket {
        guard data.count >= 17 else {
            throw MicroTechAidexParserError.invalidPacket
        }

        let glucoseRaw = Int(data.microTechUInt16(at: 6))
        return MicroTechAidexCurrentPacket(
            rawBytes: data,
            packetType: 0x01,
            trend: Int(data.microTechInt8(at: 3)),
            timeOffset: Int(data.microTechUInt16(at: 4)),
            glucoseRaw: glucoseRaw,
            glucose: glucoseRaw & 0x03FF,
            quality: (glucoseRaw >> 10) & 0x03,
            i1: Double(data.microTechInt16(at: 8)) / 100.0,
            i2: Double(data.microTechInt16(at: 10)) / 100.0,
            vc: Double(data.microTechUInt16(at: 12)) / 100.0,
            status: Int(data[data.index(data.startIndex, offsetBy: 2)]),
            byte14Flag: Int(data[data.index(data.startIndex, offsetBy: 14)])
        )
    }

    private static func parseHistory(_ data: Data) throws -> MicroTechAidexHistoryPacket {
        guard data.count >= 8 else {
            throw MicroTechAidexParserError.invalidPacket
        }

        let payloadEnd = data.count - 2
        guard (payloadEnd - 4).isMultiple(of: 2) else {
            throw MicroTechAidexParserError.invalidPacket
        }

        let startTimeOffset = Int(data.microTechUInt16(at: 2))
        var records: [MicroTechAidexHistoryRecord] = []
        var position = 4

        while position + 1 < payloadEnd {
            let rawValue = Int(data.microTechUInt16(at: position))
            if rawValue == 0xFFFF {
                break
            }

            records.append(
                MicroTechAidexHistoryRecord(
                    timeOffset: startTimeOffset + records.count,
                    glucose: rawValue & 0x03FF,
                    rawValue: rawValue
                )
            )
            position += 2
        }

        return MicroTechAidexHistoryPacket(
            rawBytes: data,
            startTimeOffset: startTimeOffset,
            records: records
        )
    }

    private static func parseStartTime(_ data: Data) -> MicroTechAidexStartTimePacket {
        MicroTechAidexStartTimePacket(
            rawBytes: data,
            startTimeByte: data.count > 2 ? data[data.index(data.startIndex, offsetBy: 2)] : 0,
            timestamp: parseDate(in: data)
        )
    }

    private static func parseDate(in data: Data) -> Date? {
        guard data.count >= 7 else {
            return nil
        }

        let bytes = [UInt8](data)
        for index in 0...(bytes.count - 7) {
            let year = Int(bytes[index]) | Int(bytes[index + 1]) << 8
            let month = Int(bytes[index + 2])
            let day = Int(bytes[index + 3])
            let hour = Int(bytes[index + 4])
            let minute = Int(bytes[index + 5])
            let second = Int(bytes[index + 6])

            guard year >= 2000 && year <= 2100,
                  month >= 1 && month <= 12,
                  day >= 1 && day <= 31,
                  hour <= 23,
                  minute <= 59,
                  second <= 59 else {
                continue
            }

            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = .current
            return calendar.date(from: DateComponents(
                year: year,
                month: month,
                day: day,
                hour: hour,
                minute: minute,
                second: second
            ))
        }

        return nil
    }
}
