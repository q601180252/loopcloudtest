import Foundation

public enum MicroTechAidexCommandBuilderError: Error, Equatable {
    case indexOutOfRange(Int)
}

public struct MicroTechAidexCommandBuilder {
    public let keyMaterial: MicroTechAidexKeyMaterial

    public init(keyMaterial: MicroTechAidexKeyMaterial) {
        self.keyMaterial = keyMaterial
    }

    public func cmd10() throws -> Data {
        try encrypt(hex: "10C1F3")
    }

    public func cmd11() throws -> Data {
        try decryptPlain(hex: "11E0E3")
    }

    public func cmd20(dateTimeBytes: Data) throws -> Data {
        var payload = Data([0x20])
        payload.append(dateTimeBytes)
        return try decryptPlain(data: MicroTechAidexCrypto.appendingCRC(to: payload))
    }

    public func cmd23(index: Int) throws -> Data {
        guard (0...0xFFFF).contains(index) else {
            throw MicroTechAidexCommandBuilderError.indexOutOfRange(index)
        }

        var payload = Data([0x23])
        payload.append(UInt8(index & 0xFF))
        payload.append(UInt8((index >> 8) & 0xFF))
        return try decryptPlain(data: MicroTechAidexCrypto.appendingCRC(to: payload))
    }

    public func cmd31() throws -> Data {
        try decryptPlain(hex: "31018A3B")
    }

    public func cmd34() throws -> Data {
        try decryptPlain(hex: "34017FC4")
    }

    public func cmd35() throws -> Data {
        try decryptPlain(hex: "35014EF7")
    }

    public func unpair() throws -> Data {
        try decryptPlain(data: MicroTechAidexCrypto.appendingCRC(to: Data([0xF2])))
    }

    public func clearStorage() throws -> Data {
        try encrypt(hex: "F38C3E")
    }

    public func decryptNotification(_ encrypted: Data) throws -> Data {
        try MicroTechAidexCrypto.decryptCfb128(key: keyMaterial.key, iv: keyMaterial.iv, cipher: encrypted)
    }

    private func encrypt(hex: String) throws -> Data {
        try MicroTechAidexCrypto.encryptCfb128(
            key: keyMaterial.key,
            iv: keyMaterial.iv,
            plain: Data(microTechHexadecimalString: hex)
        )
    }

    private func decryptPlain(hex: String) throws -> Data {
        try decryptPlain(data: Data(microTechHexadecimalString: hex))
    }

    private func decryptPlain(data: Data) throws -> Data {
        try MicroTechAidexCrypto.decryptCfb128(
            key: keyMaterial.key,
            iv: keyMaterial.iv,
            cipher: data
        )
    }
}
