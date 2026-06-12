import HealthKit
import LoopKit
import XCTest
@testable import MicroTechCGM

final class MicroTechCGMManagerTests: XCTestCase {
    func testMakeSampleConvertsReadingForLoop() {
        let manager = MicroTechCGMManager()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let reading = makeReading(sampleNumber: 42, glucoseMgdl: 123, receivedAt: date)

        let sample = manager.makeSample(from: reading)

        XCTAssertEqual(sample.quantity.doubleValue(for: Self.mgdlUnit), 123, accuracy: 0.001)
        XCTAssertEqual(sample.date, date)
        XCTAssertEqual(sample.syncIdentifier, "ABC123-42")
        XCTAssertEqual(sample.device?.manufacturer, "MicroTech Medical")
        XCTAssertEqual(sample.device?.model, "LinX")
        XCTAssertEqual(sample.trend, GlucoseTrend.down)
        XCTAssertEqual(sample.isDisplayOnly, false)
        XCTAssertEqual(sample.wasUserEntered, false)
    }

    func testAcceptReturnsSampleForFirstValidReadingAndNilForDuplicateSampleNumber() {
        let manager = MicroTechCGMManager()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let reading = makeReading(sampleNumber: 42, glucoseMgdl: 123, receivedAt: date)

        let firstSample = manager.accept(reading)
        let duplicateSample = manager.accept(reading)

        XCTAssertEqual(firstSample?.syncIdentifier, "ABC123-42")
        XCTAssertNil(duplicateSample)
        XCTAssertEqual(manager.state.sensorSerial, "ABC123")
        XCTAssertEqual(manager.state.lastReadingDate, date)
        XCTAssertEqual(manager.state.latestSampleNumber, 42)
        XCTAssertEqual(manager.glucoseDisplay as? MicroTechGlucoseReading, reading)
    }

    func testAcceptRejectsOlderSampleNumberForSameSensorSerial() {
        let manager = MicroTechCGMManager()
        let firstReading = makeReading(
            sampleNumber: 42,
            glucoseMgdl: 123,
            receivedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let latestReading = makeReading(
            sampleNumber: 43,
            glucoseMgdl: 124,
            receivedAt: Date(timeIntervalSince1970: 1_700_000_300)
        )
        let oldReading = makeReading(
            sampleNumber: 42,
            glucoseMgdl: 122,
            receivedAt: Date(timeIntervalSince1970: 1_700_000_600)
        )

        XCTAssertEqual(manager.accept(firstReading)?.syncIdentifier, "ABC123-42")
        XCTAssertEqual(manager.accept(latestReading)?.syncIdentifier, "ABC123-43")
        XCTAssertNil(manager.accept(oldReading))
        XCTAssertEqual(manager.state.latestSampleNumber, 43)
        XCTAssertEqual(manager.state.latestReading, latestReading)
        XCTAssertEqual(manager.glucoseDisplay as? MicroTechGlucoseReading, latestReading)
    }

    func testAcceptRejectsInvalidTherapyReadings() {
        let manager = MicroTechCGMManager()
        let date = Date(timeIntervalSince1970: 1_700_000_000)

        XCTAssertNil(manager.accept(makeReading(sampleNumber: 42, glucoseMgdl: 123, receivedAt: date, quality: 1)))
        XCTAssertNil(manager.accept(makeReading(sampleNumber: 43, glucoseMgdl: 39, receivedAt: date)))
        XCTAssertNil(manager.accept(makeReading(sampleNumber: 44, glucoseMgdl: 401, receivedAt: date)))
        XCTAssertNil(manager.state.latestReading)
        XCTAssertNil(manager.state.latestSampleNumber)
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

    private static let mgdlUnit = HKUnit
        .gramUnit(with: .milli)
        .unitDivided(by: .literUnit(with: .deci))
}
