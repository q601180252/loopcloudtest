import XCTest
@testable import MicroTechCGM

final class MicroTechAidexParserTests: XCTestCase {
    func testCurrentPacket() throws {
        let packet = try Data(microTechHexadecimalString: "010003FF2A007B00D204C409B80B0100003FC5")
        let parsed = try MicroTechAidexParser.parse(packet)
        guard case .current(let current) = parsed else {
            return XCTFail("Expected current packet")
        }
        XCTAssertEqual(0x01, current.packetType)
        XCTAssertEqual(-1, current.trend)
        XCTAssertEqual(42, current.timeOffset)
        XCTAssertEqual(123, current.glucose)
        XCTAssertEqual(0, current.quality)
        XCTAssertEqual(12.34, current.i1)
        XCTAssertEqual(25.0, current.i2)
        XCTAssertEqual(30.0, current.vc)
        XCTAssertEqual(3, current.status)
        XCTAssertEqual(1, current.byte14Flag)
    }

    func testHistoryPacket() throws {
        let packet = try Data(microTechHexadecimalString: "2300E8036F007000FFFFFB1A")
        let parsed = try MicroTechAidexParser.parse(packet)
        guard case .history(let history) = parsed else {
            return XCTFail("Expected history packet")
        }
        XCTAssertEqual(1000, history.startTimeOffset)
        XCTAssertEqual(2, history.records.count)
        XCTAssertEqual(1000, history.records[0].timeOffset)
        XCTAssertEqual(111, history.records[0].glucose)
        XCTAssertEqual(1001, history.records[1].timeOffset)
        XCTAssertEqual(112, history.records[1].glucose)
    }

    func testInvalidCRCThrows() throws {
        let packet = try Data(microTechHexadecimalString: "010003FF2A007B00D204C409B80B0100003FC4")
        XCTAssertThrowsError(try MicroTechAidexParser.parse(packet)) { error in
            XCTAssertEqual(error as? MicroTechAidexParserError, .invalidCRC)
        }
    }

    func testReadingConversionFiltersInvalidValues() throws {
        let packet = try Data(microTechHexadecimalString: "010003FF2A007B00D204C409B80B0100003FC5")
        let parsed = try MicroTechAidexParser.parse(packet)
        guard case .current(let current) = parsed else {
            return XCTFail("Expected current packet")
        }
        let reading = MicroTechGlucoseReading(current: current, sensorSerial: "ABC123", receivedAt: Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(123, reading.glucoseMgdl)
        XCTAssertEqual("ABC123-42", reading.syncIdentifier)
        XCTAssertEqual(.flat, reading.trendType)
    }
}
