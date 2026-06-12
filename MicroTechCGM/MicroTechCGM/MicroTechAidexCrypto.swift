import CommonCrypto
import CryptoKit
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

    public static func encryptCfb128(key: Data, iv: Data, plain: Data) throws -> Data {
        try cfb128(key: key, iv: iv, input: plain, isEncrypting: true)
    }

    public static func decryptCfb128(key: Data, iv: Data, cipher: Data) throws -> Data {
        try cfb128(key: key, iv: iv, input: cipher, isEncrypting: false)
    }

    private static func cfb128(key: Data, iv: Data, input: Data, isEncrypting: Bool) throws -> Data {
        guard key.count == kCCKeySizeAES128 else {
            throw MicroTechAidexCryptoError.invalidKeyLength(key.count)
        }
        guard iv.count == kCCBlockSizeAES128 else {
            throw MicroTechAidexCryptoError.invalidIVLength(iv.count)
        }

        var feedback = [UInt8](iv)
        var output = Data()
        output.reserveCapacity(input.count)

        var keyStream: [UInt8] = []
        var offset = 0
        for byte in input {
            if offset == 0 {
                keyStream = try aesEncryptBlock(Data(feedback), key: key)
            }

            let transformed = byte ^ keyStream[offset]
            output.append(transformed)
            feedback[offset] = isEncrypting ? transformed : byte
            offset = (offset + 1) % kCCBlockSizeAES128
        }

        return output
    }

    private static func aesEncryptBlock(_ block: Data, key: Data) throws -> [UInt8] {
        var output = [UInt8](repeating: 0, count: kCCBlockSizeAES128)
        let outputCapacity = output.count
        var outputLength = 0

        let status = key.withUnsafeBytes { keyBytes in
            block.withUnsafeBytes { blockBytes in
                output.withUnsafeMutableBytes { outputBytes in
                    CCCrypt(
                        CCOperation(kCCEncrypt),
                        CCAlgorithm(kCCAlgorithmAES),
                        CCOptions(kCCOptionECBMode),
                        keyBytes.baseAddress,
                        key.count,
                        nil,
                        blockBytes.baseAddress,
                        block.count,
                        outputBytes.baseAddress,
                        outputCapacity,
                        &outputLength
                    )
                }
            }
        }

        guard status == kCCSuccess else {
            throw MicroTechAidexCryptoError.aesFailure(Int32(status))
        }

        return Array(output.prefix(outputLength))
    }
}

public struct MicroTechAidexKeyMaterial: Equatable {
    public let sensorSerial: String
    public let key: Data
    public let iv: Data

    public static func derive(deviceName: String) -> MicroTechAidexKeyMaterial {
        guard let separator = deviceName.lastIndex(of: "-") else {
            return derive(serial: deviceName)
        }

        let serialStart = deviceName.index(after: separator)
        guard serialStart < deviceName.endIndex else {
            return derive(serial: deviceName)
        }

        return derive(serial: String(deviceName[serialStart...]))
    }

    public static func derive(serial: String) -> MicroTechAidexKeyMaterial {
        let mapped = serial.unicodeScalars.map { scalar in
            mappedSerialByte(for: scalar)
        }
        let keyInput = Data(mapped.map { byte in
            UInt8((Int(byte) * 13 + 61) & 0xFF)
        })
        let ivInput = Data(mapped.map { byte in
            UInt8((Int(byte) * 17 + 19) & 0xFF)
        })

        return MicroTechAidexKeyMaterial(
            sensorSerial: serial,
            key: md5(keyInput),
            iv: md5(ivInput)
        )
    }

    public static func deriveSessionMaterial(
        baseMaterial: MicroTechAidexKeyMaterial,
        encryptedChallenge: Data,
        pairingKey: Data
    ) throws -> MicroTechAidexKeyMaterial {
        guard !encryptedChallenge.isEmpty else {
            throw MicroTechAidexCryptoError.emptyChallenge
        }

        let normalizedPairingKey = try normalizeKey(pairingKey)
        let plainChallenge = try MicroTechAidexCrypto.decryptCfb128(
            key: normalizedPairingKey,
            iv: baseMaterial.iv,
            cipher: encryptedChallenge
        )
        let sessionKey = try normalizeKey(plainChallenge)
        return MicroTechAidexKeyMaterial(
            sensorSerial: baseMaterial.sensorSerial,
            key: sessionKey,
            iv: baseMaterial.iv
        )
    }

    public static func normalizeKey(_ key: Data) throws -> Data {
        guard key.count >= kCCKeySizeAES128 else {
            throw MicroTechAidexCryptoError.keyTooShort(key.count)
        }
        return Data(key.prefix(kCCKeySizeAES128))
    }

    private static func mappedSerialByte(for scalar: Unicode.Scalar) -> UInt8 {
        switch scalar.value {
        case 48...57:
            return UInt8(scalar.value - 48)
        case 65...90:
            return UInt8(scalar.value - 65 + 10)
        case 97...122:
            return UInt8(scalar.value - 97 + 10)
        default:
            return UInt8(truncatingIfNeeded: scalar.value)
        }
    }

    private static func md5(_ data: Data) -> Data {
        Data(Insecure.MD5.hash(data: data))
    }
}
