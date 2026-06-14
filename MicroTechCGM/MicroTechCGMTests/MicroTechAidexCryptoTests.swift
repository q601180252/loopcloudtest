import XCTest
@testable import MicroTechCGM

final class MicroTechAidexCryptoTests: XCTestCase {
    func testProfileUUIDs() {
        XCTAssertEqual("0000181F-0000-1000-8000-00805F9B34FB", MicroTechAidexProfile.serviceUUID.uuidString)
        XCTAssertEqual("0000F001-0000-1000-8000-00805F9B34FB", MicroTechAidexProfile.f001UUID.uuidString)
        XCTAssertEqual("0000F002-0000-1000-8000-00805F9B34FB", MicroTechAidexProfile.f002UUID.uuidString)
        XCTAssertEqual("0000F003-0000-1000-8000-00805F9B34FB", MicroTechAidexProfile.f003UUID.uuidString)
    }

    func testHexRoundTripAndLittleEndian() throws {
        let data = try Data(microTechHexadecimalString: "01 02 0A ff")
        XCTAssertEqual("01020AFF", data.microTechHexadecimalString)
        XCTAssertEqual(0x0201, data.microTechUInt16(at: 0))
        XCTAssertEqual(-246, Data([0x0A, 0xFF]).microTechInt16(at: 0))
        XCTAssertEqual(-1, Data([0xFF]).microTechInt8(at: 0))
    }

    func testCRC16Ccitt() throws {
        let data = Data([0x01, 0x02, 0x03])
        XCTAssertEqual(0xADAD, MicroTechAidexCrypto.crc16Ccitt(data))
        XCTAssertEqual(try Data(microTechHexadecimalString: "010203ADAD"), MicroTechAidexCrypto.appendingCRC(to: data))
        XCTAssertTrue(MicroTechAidexCrypto.hasValidTrailingCRC(try Data(microTechHexadecimalString: "010203ADAD")))
        XCTAssertFalse(MicroTechAidexCrypto.hasValidTrailingCRC(try Data(microTechHexadecimalString: "010203ADAE")))
    }

    func testSerialKeyDerivation() throws {
        let material = MicroTechAidexKeyMaterial.derive(serial: "ABC123")
        XCTAssertEqual("ABC123", material.sensorSerial)
        XCTAssertEqual("C21D3C97C38DD60B2B0E129EC9EA1C84", material.key.microTechHexadecimalString)
        XCTAssertEqual("5A837629840E30374590EE4D7DF612DE", material.iv.microTechHexadecimalString)

        let fromName = MicroTechAidexKeyMaterial.derive(deviceName: "LinX-ABC123")
        XCTAssertEqual(material, fromName)

        let scalarMappedMaterial = MicroTechAidexKeyMaterial.derive(serial: "abc-1")
        XCTAssertEqual("abc-1", scalarMappedMaterial.sensorSerial)
        XCTAssertEqual("E8A7B0FF3AC85B73EB31046584A2BB04", scalarMappedMaterial.key.microTechHexadecimalString)
        XCTAssertEqual("E03D7C658C2210CAEDDEAD525F5D82BA", scalarMappedMaterial.iv.microTechHexadecimalString)
    }

    func testAESCfbRoundTrip() throws {
        let material = MicroTechAidexKeyMaterial.derive(serial: "ABC123")
        let plain = try Data(microTechHexadecimalString: "010003FF2A007B00D204C409B80B0100003FC5")
        let encrypted = try MicroTechAidexCrypto.encryptCfb128(key: material.key, iv: material.iv, plain: plain)
        XCTAssertEqual("A11963C33AD331B94B3352FFBF39B9455B9C01", encrypted.microTechHexadecimalString)
        let decrypted = try MicroTechAidexCrypto.decryptCfb128(key: material.key, iv: material.iv, cipher: encrypted)
        XCTAssertEqual(plain, decrypted)
    }

    func testCommandBuilderVectors() throws {
        let builder = MicroTechAidexCommandBuilder(keyMaterial: .derive(serial: "ABC123"))
        XCTAssertEqual("B0D893", try builder.cmd10().microTechHexadecimalString)
        XCTAssertEqual("B1F983", try builder.cmd11().microTechHexadecimalString)
        XCTAssertEqual("80F1673A1CD954B9B937A1D4", try builder.cmd20(dateTimeBytes: Data(microTechHexadecimalString: "E807060C0A1E002000")).microTechHexadecimalString)
        XCTAssertEqual("9118EA07", try builder.cmd31().microTechHexadecimalString)
        XCTAssertEqual("94181FF8", try builder.cmd34().microTechHexadecimalString)
        XCTAssertEqual("95182ECB", try builder.cmd35().microTechHexadecimalString)
        XCTAssertEqual("8333601BEA", try builder.cmd23(index: 42).microTechHexadecimalString)
        XCTAssertEqual("53955E", try builder.clearStorage().microTechHexadecimalString)
        XCTAssertEqual("52B44E", try builder.unpair().microTechHexadecimalString)
    }

    func testCommandBuilderRejectsOutOfRangeHistoryIndex() throws {
        let builder = MicroTechAidexCommandBuilder(keyMaterial: .derive(serial: "ABC123"))

        XCTAssertThrowsError(try builder.cmd23(index: -1)) { error in
            XCTAssertEqual(error as? MicroTechAidexCommandBuilderError, .indexOutOfRange(-1))
        }
        XCTAssertThrowsError(try builder.cmd23(index: 65536)) { error in
            XCTAssertEqual(error as? MicroTechAidexCommandBuilderError, .indexOutOfRange(65536))
        }
    }

    func testDecryptNotificationVector() throws {
        let builder = MicroTechAidexCommandBuilder(keyMaterial: .derive(serial: "ABC123"))
        let encrypted = try Data(microTechHexadecimalString: "A11963C33AD331B94B3352FFBF39B9455B9C01")
        let plain = try builder.decryptNotification(encrypted)
        XCTAssertEqual("010003FF2A007B00D204C409B80B0100003FC5", plain.microTechHexadecimalString)
    }

    func testSessionMaterialFromChallenge() throws {
        let base = MicroTechAidexKeyMaterial.derive(serial: "ABC123")
        let pairingKey = base.key
        let plainSessionKey = try Data(microTechHexadecimalString: "00112233445566778899AABBCCDDEEFF")
        let encryptedChallenge = try MicroTechAidexCrypto.encryptCfb128(key: pairingKey, iv: base.iv, plain: plainSessionKey)
        let session = try MicroTechAidexKeyMaterial.deriveSessionMaterial(baseMaterial: base, encryptedChallenge: encryptedChallenge, pairingKey: pairingKey)
        XCTAssertEqual("00112233445566778899AABBCCDDEEFF", session.key.microTechHexadecimalString)
        XCTAssertEqual(base.iv, session.iv)
    }
}
