import XCTest
@testable import MicroTechCGM

final class MicroTechAidexParserTests: XCTestCase {
    func testBroadcastParserParsesAdvertisementAndManufacturerPayloads() throws {
        let advertisingPayload = try Data(microTechHexadecimalString: "02010603021f1817ff590060540100026e80436c80416a80410000f33ee04e1309416944455820582d3232323232374a4b464b08ff590003f9054b360000")
        let manufacturerData = try Data(microTechHexadecimalString: "590060540100026e80436c80416a80410000f33ee04e")
        let manufacturerPayload = try Data(microTechHexadecimalString: "60540100026e80436c80416a80410000f33ee04e")

        let fromAdvertisement = try MicroTechAidexBroadcastParser.parseAdvertisementData([
            "kCBAdvDataManufacturerData": manufacturerData,
        ])
        let fromAdvertisingPayload = try MicroTechAidexBroadcastParser.parseAdvertisingPayload(advertisingPayload)
        let fromManufacturerPayload = try MicroTechAidexBroadcastParser.parseManufacturerPayload(manufacturerPayload)

        for reading in [fromAdvertisement, fromAdvertisingPayload, fromManufacturerPayload] {
            XCTAssertEqual(reading.timeOffset, 21_600)
            XCTAssertEqual(reading.status, 1)
            XCTAssertEqual(reading.calibrationTemperature, 0)
            XCTAssertEqual(reading.trend, 2)
            XCTAssertEqual(reading.records, [
                MicroTechAidexBroadcastRecord(timeOffset: 21_600, glucose: 110, reserved: 0x80, quality: 67),
                MicroTechAidexBroadcastRecord(timeOffset: 21_599, glucose: 108, reserved: 0x80, quality: 65),
                MicroTechAidexBroadcastRecord(timeOffset: 21_598, glucose: 106, reserved: 0x80, quality: 65),
            ])
            XCTAssertEqual(reading.latestRecord, reading.records.first)
            XCTAssertEqual(reading.rawManufacturerPayload, manufacturerPayload)
        }
    }

    func testBroadcastParserParsesNegativeTrend() throws {
        let payload = try Data(microTechHexadecimalString: "60540100fe6e80436c80416a80410000f33ee04e")

        let reading = try MicroTechAidexBroadcastParser.parseManufacturerPayload(payload)

        XCTAssertEqual(reading.trend, -2)
    }

    func testBroadcastParserRejectsInvalidManufacturerData() throws {
        XCTAssertThrowsError(try MicroTechAidexBroadcastParser.parseAdvertisementData([:])) { error in
            XCTAssertEqual(error as? MicroTechAidexBroadcastParserError, .missingManufacturerData)
        }

        XCTAssertThrowsError(try MicroTechAidexBroadcastParser.parseAdvertisementData([
            "kCBAdvDataManufacturerData": Data([0x58, 0x00, 0x60, 0x54, 0x01]),
        ])) { error in
            XCTAssertEqual(error as? MicroTechAidexBroadcastParserError, .wrongCompanyIdentifier)
        }

        XCTAssertThrowsError(try MicroTechAidexBroadcastParser.parseManufacturerPayload(Data([0x60, 0x54, 0x01, 0x00]))) { error in
            XCTAssertEqual(error as? MicroTechAidexBroadcastParserError, .payloadTooShort)
        }

        XCTAssertThrowsError(try MicroTechAidexBroadcastParser.parseManufacturerPayload(Data([0x60, 0x54, 0x01, 0x00, 0x02]))) { error in
            XCTAssertEqual(error as? MicroTechAidexBroadcastParserError, .noRecords)
        }

        let invalidGlucose = try Data(microTechHexadecimalString: "6054010002208043")
        XCTAssertThrowsError(try MicroTechAidexBroadcastParser.parseManufacturerPayload(invalidGlucose)) { error in
            XCTAssertEqual(error as? MicroTechAidexBroadcastParserError, .invalidGlucose(32))
        }
    }

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

    func testLinxF003CurrentPacketFromDeviceLog() throws {
        let packet = try Data(microTechHexadecimalString: "030100FE60545F80B303800C4500004D5B")
        let parsed = try MicroTechAidexParser.parse(packet)
        guard case .current(let current) = parsed else {
            return XCTFail("Expected current packet")
        }
        XCTAssertEqual(0x03, current.packetType)
        XCTAssertEqual(-2, current.trend)
        XCTAssertEqual(21600, current.timeOffset)
        XCTAssertEqual(95, current.glucose)
        XCTAssertEqual(0, current.quality)
        XCTAssertEqual(9.47, current.i1)
        XCTAssertEqual(32.0, current.i2)
        XCTAssertEqual(0.69, current.vc)
        XCTAssertEqual(0, current.status)
        XCTAssertEqual(0, current.byte14Flag)
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

    func testHistoryPacketWrapsTimeOffsetAfterUInt16Max() throws {
        let payload = Data([0x23, 0x00, 0xFF, 0xFF, 0x6F, 0x00, 0x70, 0x00, 0x71, 0x00, 0xFF, 0xFF])
        let packet = MicroTechAidexCrypto.appendingCRC(to: payload)
        let parsed = try MicroTechAidexParser.parse(packet)
        guard case .history(let history) = parsed else {
            return XCTFail("Expected history packet")
        }
        XCTAssertEqual(65535, history.startTimeOffset)
        XCTAssertEqual([65535, 0, 1], history.records.map(\.timeOffset))
        XCTAssertEqual([111, 112, 113], history.records.map(\.glucose))
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
        XCTAssertEqual(-1, reading.trend)
        XCTAssertEqual("ABC123-42", reading.syncIdentifier)
        XCTAssertEqual(.down, reading.trendType)
    }
}
