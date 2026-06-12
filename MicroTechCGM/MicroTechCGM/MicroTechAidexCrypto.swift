import Foundation

public enum MicroTechAidexCryptoError: Error, Equatable {
    case invalidKeyLength(Int)
    case invalidIVLength(Int)
    case aesFailure(Int32)
    case emptyChallenge
    case keyTooShort(Int)
}

public enum MicroTechAidexCrypto {
    public static func crc16Ccitt(_ data: Data) -> UInt16 {
        var crc: UInt16 = 0xFFFF
        for byte in data {
            crc ^= UInt16(byte) << 8
            for _ in 0..<8 {
                if crc & 0x8000 != 0 {
                    crc = (crc << 1) ^ 0x1021
                } else {
                    crc <<= 1
                }
            }
        }
        return crc
    }

    public static func appendingCRC(to payload: Data) -> Data {
        let crc = crc16Ccitt(payload)
        var data = payload
        data.append(UInt8(crc & 0x00FF))
        data.append(UInt8((crc >> 8) & 0x00FF))
        return data
    }

    public static func hasValidTrailingCRC(_ packet: Data) -> Bool {
        guard packet.count >= 3 else {
            return false
        }
        let payload = packet.dropLast(2)
        let expected = packet.microTechUInt16(at: packet.count - 2)
        return crc16Ccitt(Data(payload)) == expected
    }
}
