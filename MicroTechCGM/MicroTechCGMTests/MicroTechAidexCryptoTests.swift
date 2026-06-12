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
}
