import CoreBluetooth
import XCTest
@testable import MicroTechCGM

final class MicroTechSensorHandshakeTests: XCTestCase {
    func testHandshakeOrder() throws {
        let material = MicroTechAidexKeyMaterial.derive(serial: "ABC123")
        XCTAssertEqual("C21D3C97C38DD60B2B0E129EC9EA1C84", material.key.microTechHexadecimalString)

        let fake = FakeMicroTechPeripheralSession(
            deviceIdentifier: UUID(uuidString: "00000000-0000-0000-0000-000000000123")!,
            deviceName: "LinX-ABC123",
            f002Challenge: try encryptedChallenge(for: material)
        )
        let sensor = MicroTechSensor(
            session: MicroTechAidexSession(
                remoteIdentifier: fake.deviceIdentifier,
                deviceName: fake.deviceName,
                sensorSerial: "ABC123"
            ),
            peripheralSession: fake
        )

        try sensor.start()

        XCTAssertEqual([
            .subscribe(MicroTechAidexProfile.f002UUID.uuidString),
            .subscribe(MicroTechAidexProfile.f001UUID.uuidString),
            .write(material.key.microTechHexadecimalString, MicroTechAidexProfile.f001UUID.uuidString),
            .write(material.key.microTechHexadecimalString, MicroTechAidexProfile.f001UUID.uuidString),
            .read(MicroTechAidexProfile.f002UUID.uuidString),
            .subscribe(MicroTechAidexProfile.f003UUID.uuidString),
            .write("B0D893", MicroTechAidexProfile.f002UUID.uuidString),
        ], fake.calls)
    }

    func testHandshakeUsesSessionSerialWhenDeviceNameDoesNotContainSerial() throws {
        let material = MicroTechAidexKeyMaterial.derive(serial: "ABC123")
        let fake = FakeMicroTechPeripheralSession(
            deviceIdentifier: UUID(uuidString: "00000000-0000-0000-0000-000000000123")!,
            deviceName: "AiDEX",
            f002Challenge: try encryptedChallenge(for: material)
        )
        let sensor = MicroTechSensor(
            session: MicroTechAidexSession(
                remoteIdentifier: fake.deviceIdentifier,
                deviceName: fake.deviceName,
                sensorSerial: "ABC123"
            ),
            peripheralSession: fake
        )

        try sensor.start()

        XCTAssertEqual([
            .subscribe(MicroTechAidexProfile.f002UUID.uuidString),
            .subscribe(MicroTechAidexProfile.f001UUID.uuidString),
            .write(material.key.microTechHexadecimalString, MicroTechAidexProfile.f001UUID.uuidString),
            .write(material.key.microTechHexadecimalString, MicroTechAidexProfile.f001UUID.uuidString),
            .read(MicroTechAidexProfile.f002UUID.uuidString),
            .subscribe(MicroTechAidexProfile.f003UUID.uuidString),
            .write("B0D893", MicroTechAidexProfile.f002UUID.uuidString),
        ], fake.calls)
    }

    func testF003NotificationEmitsCurrentReading() throws {
        let material = MicroTechAidexKeyMaterial.derive(serial: "ABC123")
        let plain = try Data(microTechHexadecimalString: "010003FF2A007B00D204C409B80B0100003FC5")
        let encrypted = try MicroTechAidexCrypto.encryptCfb128(key: material.key, iv: material.iv, plain: plain)
        let receivedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let fake = FakeMicroTechPeripheralSession(
            deviceIdentifier: UUID(uuidString: "00000000-0000-0000-0000-000000000123")!,
            deviceName: "LinX-ABC123",
            f002Challenge: try encryptedChallenge(for: material)
        )
        let observer = ReadingObserver()
        let sensor = MicroTechSensor(
            session: MicroTechAidexSession(
                remoteIdentifier: fake.deviceIdentifier,
                deviceName: fake.deviceName,
                sensorSerial: "ABC123"
            ),
            peripheralSession: fake
        )
        sensor.delegate = observer

        try sensor.start()
        sensor.handleNotification(
            characteristic: MicroTechAidexProfile.f003UUID,
            value: encrypted,
            receivedAt: receivedAt
        )

        let reading = try XCTUnwrap(observer.readings.single)
        XCTAssertEqual(123, reading.glucoseMgdl)
        XCTAssertEqual(42, reading.sampleNumber)
        XCTAssertEqual(receivedAt, reading.receivedAt)
        XCTAssertEqual("ABC123", reading.sensorSerial)
        XCTAssertTrue(observer.historyPackets.isEmpty)
        XCTAssertTrue(observer.errors.isEmpty)
    }

    private func encryptedChallenge(for material: MicroTechAidexKeyMaterial) throws -> Data {
        try MicroTechAidexCrypto.encryptCfb128(key: material.key, iv: material.iv, plain: material.key)
    }
}

final class FakeMicroTechPeripheralSession: MicroTechPeripheralSession {
    enum Call: Equatable {
        case subscribe(String)
        case write(String, String)
        case read(String)
        case disconnect
    }

    let deviceIdentifier: UUID
    let deviceName: String
    private let f002Challenge: Data
    private(set) var calls: [Call] = []

    init(deviceIdentifier: UUID, deviceName: String, f002Challenge: Data) {
        self.deviceIdentifier = deviceIdentifier
        self.deviceName = deviceName
        self.f002Challenge = f002Challenge
    }

    func subscribe(_ characteristic: CBUUID) throws {
        calls.append(.subscribe(characteristic.uuidString))
    }

    func write(_ value: Data, to characteristic: CBUUID) throws {
        calls.append(.write(value.microTechHexadecimalString, characteristic.uuidString))
    }

    func read(_ characteristic: CBUUID) throws -> Data {
        calls.append(.read(characteristic.uuidString))
        return f002Challenge
    }

    func disconnect() {
        calls.append(.disconnect)
    }
}

final class ReadingObserver: MicroTechSensorDelegate {
    private(set) var readings: [MicroTechGlucoseReading] = []
    private(set) var historyPackets: [MicroTechAidexHistoryPacket] = []
    private(set) var errors: [Error] = []
    private(set) var connectedSessions: [MicroTechAidexSession] = []
    private(set) var disconnectCount = 0

    func microTechSensor(_ sensor: MicroTechSensor, didRead reading: MicroTechGlucoseReading) {
        readings.append(reading)
    }

    func microTechSensor(_ sensor: MicroTechSensor, didReadHistory history: MicroTechAidexHistoryPacket) {
        historyPackets.append(history)
    }

    func microTechSensor(_ sensor: MicroTechSensor, didError error: Error) {
        errors.append(error)
    }

    func microTechSensorDidConnect(_ sensor: MicroTechSensor, session: MicroTechAidexSession) {
        connectedSessions.append(session)
    }

    func microTechSensorDidDisconnect(_ sensor: MicroTechSensor) {
        disconnectCount += 1
    }
}

extension Array {
    var single: Element? {
        count == 1 ? self[0] : nil
    }
}
