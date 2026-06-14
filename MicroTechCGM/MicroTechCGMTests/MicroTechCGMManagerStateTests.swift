import XCTest
@testable import MicroTechCGM

final class MicroTechCGMManagerStateTests: XCTestCase {
    func testRawStateRoundTripPersistsScalarFields() {
        let remoteIdentifier = UUID(uuidString: "90FB6D6F-1E69-460B-A8A7-F9B80540859B")!
        let activationTime = Date(timeIntervalSince1970: 1_699_999_000)
        let lastReadingDate = Date(timeIntervalSince1970: 1_700_000_000)
        let latestReading = makeReading(
            sampleNumber: 42,
            glucoseMgdl: 123,
            receivedAt: lastReadingDate
        )

        var state = MicroTechCGMManagerState()
        state.remoteIdentifier = remoteIdentifier
        state.deviceName = "LinX-ABC123"
        state.sensorSerial = "ABC123"
        state.activationTime = activationTime
        state.lastReadingDate = lastReadingDate
        state.latestReading = latestReading
        state.latestSampleNumber = 42
        state.uploadReadings = true

        let restored = MicroTechCGMManagerState(rawValue: state.rawValue)

        XCTAssertEqual(restored.remoteIdentifier, remoteIdentifier)
        XCTAssertEqual(restored.deviceName, "LinX-ABC123")
        XCTAssertEqual(restored.sensorSerial, "ABC123")
        XCTAssertEqual(restored.activationTime, activationTime)
        XCTAssertEqual(restored.lastReadingDate, lastReadingDate)
        XCTAssertEqual(restored.latestSampleNumber, 42)
        XCTAssertEqual(restored.uploadReadings, true)
        XCTAssertNil(restored.latestReading)
    }

    private func makeReading(
        sampleNumber: Int,
        glucoseMgdl: Int,
        receivedAt: Date,
        quality: Int = 0
    ) -> MicroTechGlucoseReading {
        let packet = MicroTechAidexCurrentPacket(
            rawBytes: Data([0x01]),
            packetType: 0x01,
            trend: -1,
            timeOffset: sampleNumber,
            glucoseRaw: glucoseMgdl,
            glucose: glucoseMgdl,
            quality: quality,
            i1: 0,
            i2: 0,
            vc: 0,
            status: 0,
            byte14Flag: 0
        )
        return MicroTechGlucoseReading(
            current: packet,
            sensorSerial: "ABC123",
            receivedAt: receivedAt
        )
    }
}
