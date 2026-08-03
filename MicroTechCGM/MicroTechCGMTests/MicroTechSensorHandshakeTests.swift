import CoreBluetooth
import XCTest
@testable import MicroTechCGM

final class MicroTechSensorHandshakeTests: XCTestCase {
    func testF001ReportsRawPacketBeforePairingResponseReturns() {
        let fake = FakeMicroTechPeripheralSession(
            deviceIdentifier: UUID(uuidString: "00000000-0000-0000-0000-000000000123")!,
            deviceName: "LinX-ABC123",
            f002Challenge: Data()
        )
        let observer = ReadingObserver()
        let sensor = MicroTechSensor(
            session: MicroTechAidexSession(
                remoteIdentifier: fake.deviceIdentifier,
                deviceName: fake.deviceName,
                sensorSerial: "ABC123"
            ),
            peripheralSession: fake,
            pairingKeyTimeout: 0
        )
        let receivedAt = Date(timeIntervalSince1970: 1_700_000_001)
        sensor.delegate = observer

        sensor.handleNotification(
            characteristic: MicroTechAidexProfile.f001UUID,
            value: Data(repeating: 0xAB, count: 16),
            receivedAt: receivedAt
        )
        observer.notificationEvents.append("pairing-return")

        XCTAssertEqual(observer.notificationEvents, ["packet:F001", "pairing-store", "pairing-return"])
        XCTAssertEqual(observer.packetNotifications.count, 1)
        XCTAssertEqual(observer.packetNotifications.single?.characteristic, MicroTechAidexProfile.f001UUID)
        XCTAssertEqual(observer.packetNotifications.single?.receivedAt, receivedAt)
    }

    func testF002ReportsRawPacketBeforeDecryptFailure() throws {
        let material = MicroTechAidexKeyMaterial.derive(serial: "ABC123")
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
            peripheralSession: fake,
            pairingKeyTimeout: 0,
            commandScheduler: nil,
            notificationDecrypter: { _, _ in
                observer.notificationEvents.append("decrypt")
                throw MicroTechSensorHandshakeTestError.forcedFailure
            }
        )
        sensor.delegate = observer
        try sensor.start()

        sensor.handleNotification(
            characteristic: MicroTechAidexProfile.f002UUID,
            value: Data([0x01]),
            receivedAt: Date(timeIntervalSince1970: 1_700_000_002)
        )

        XCTAssertEqual(observer.notificationEvents, ["packet:F002", "decrypt", "error"])
        XCTAssertEqual(observer.packetNotifications.map(\.characteristic), [MicroTechAidexProfile.f002UUID])
    }

    func testF003ReportsRawPacketBeforeParseFailure() throws {
        let material = MicroTechAidexKeyMaterial.derive(serial: "ABC123")
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
            peripheralSession: fake,
            pairingKeyTimeout: 0
        )
        sensor.delegate = observer
        try sensor.start()
        let invalidPlain = MicroTechAidexCrypto.appendingCRC(to: Data([0x03]))
        let encrypted = try MicroTechAidexCrypto.encryptCfb128(
            key: material.key,
            iv: material.iv,
            plain: invalidPlain
        )

        sensor.handleNotification(
            characteristic: MicroTechAidexProfile.f003UUID,
            value: encrypted,
            receivedAt: Date(timeIntervalSince1970: 1_700_000_003)
        )

        XCTAssertEqual(observer.notificationEvents, ["packet:F003", "error"])
        XCTAssertEqual(observer.packetNotifications.map(\.characteristic), [MicroTechAidexProfile.f003UUID])
    }

    func testUnrelatedCharacteristicDoesNotReportRawPacket() throws {
        let material = MicroTechAidexKeyMaterial.derive(serial: "ABC123")
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
            peripheralSession: fake,
            pairingKeyTimeout: 0
        )
        sensor.delegate = observer
        try sensor.start()

        sensor.handleNotification(characteristic: CBUUID(string: "180D"), value: Data([0x01]))

        XCTAssertTrue(observer.packetNotifications.isEmpty)
        XCTAssertTrue(observer.notificationEvents.isEmpty)
    }

    func testPeripheralOperationTimeoutLeavesRoomForRestoredConnectionHandshake() {
        XCTAssertGreaterThanOrEqual(MicroTechPeripheralManager.defaultOperationTimeout, 8)
    }

    func testHandshakeLogsCompleteBasePairingAndSessionMaterial() throws {
        let material = MicroTechAidexKeyMaterial.derive(serial: "ABC123")
        let rawPairingKey = Data((0..<40).map { UInt8(0x80 + $0) })
        let pairingKey = Data(rawPairingKey.prefix(16))
        let sessionKey = Data((0..<16).map { UInt8($0 + 1) })
        let challenge = try MicroTechAidexCrypto.encryptCfb128(
            key: pairingKey,
            iv: material.iv,
            plain: sessionKey + Data([0x00])
        )
        let fake = FakeMicroTechPeripheralSession(
            deviceIdentifier: UUID(uuidString: "00000000-0000-0000-0000-000000000123")!,
            deviceName: "LinX-ABC123",
            f002Challenge: challenge
        )
        let observer = ReadingObserver()
        let sensor = MicroTechSensor(
            session: MicroTechAidexSession(
                remoteIdentifier: fake.deviceIdentifier,
                deviceName: fake.deviceName,
                sensorSerial: "ABC123"
            ),
            peripheralSession: fake,
            pairingKeyTimeout: 0
        )
        fake.onWrite = { value, characteristic in
            guard characteristic == MicroTechAidexProfile.f001UUID, value == material.key else {
                return
            }
            sensor.handleNotification(characteristic: MicroTechAidexProfile.f001UUID, value: rawPairingKey)
        }
        sensor.delegate = observer

        try sensor.start()

        XCTAssertTrue(observer.logMessages.contains { log in
            log.message == "stage=handshake event=base_material serial=ABC123 baseKey=\(material.key.microTechHexadecimalString) baseIV=\(material.iv.microTechHexadecimalString)"
        })
        XCTAssertTrue(observer.logMessages.contains { log in
            log.message == "stage=handshake event=pairing_key source=f001 rawPairingKey=\(rawPairingKey.microTechHexadecimalString) pairingKey=\(pairingKey.microTechHexadecimalString)"
        })
        XCTAssertTrue(observer.logMessages.contains { log in
            log.message == "stage=handshake event=challenge characteristic=F002 len=\(challenge.count) challengeHex=\(challenge.microTechHexadecimalString)"
        })
        XCTAssertTrue(observer.logMessages.contains { log in
            log.message == "stage=handshake event=session_material sessionKey=\(sessionKey.microTechHexadecimalString) sessionIV=\(material.iv.microTechHexadecimalString)"
        })
        XCTAssertTrue(observer.logMessages.allSatisfy { log in
            !log.message.contains("rawPrefix") &&
                !log.message.contains("hexPrefix") &&
                !log.message.contains("...")
        })
    }

    func testHandshakeLogsCompleteCommandsBeforeWrite() throws {
        let material = MicroTechAidexKeyMaterial.derive(serial: "ABC123")
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
            peripheralSession: fake,
            pairingKeyTimeout: 0
        )
        var writeIndex = 0
        let expectedWrites = [
            (MicroTechAidexProfile.f001UUID, "F001", "base_key", material.key),
            (MicroTechAidexProfile.f001UUID, "F001", "pairing_response", material.key),
            (MicroTechAidexProfile.f002UUID, "F002", "cmd10", try MicroTechAidexCommandBuilder(keyMaterial: material).cmd10()),
        ]
        fake.onWrite = { value, characteristic in
            let expected = expectedWrites[writeIndex]
            XCTAssertEqual(value, expected.3)
            XCTAssertEqual(characteristic, expected.0)
            XCTAssertTrue(observer.logMessages.contains { log in
                log.message == self.packetLog(
                    event: "send_attempted",
                    characteristic: expected.1,
                    command: expected.2,
                    data: expected.3
                )
            })
            writeIndex += 1
        }
        sensor.delegate = observer

        try sensor.start()

        XCTAssertEqual(writeIndex, expectedWrites.count)
        for expected in expectedWrites {
            XCTAssertTrue(observer.logMessages.contains { log in
                log.message == packetLog(
                    event: "send_succeeded",
                    characteristic: expected.1,
                    command: expected.2,
                    data: expected.3
                )
            })
        }
    }

    func testDecryptFailureKeepsCompleteEncryptedPacket() throws {
        let material = MicroTechAidexKeyMaterial.derive(serial: "ABC123")
        let encrypted = Data((0..<48).map(UInt8.init))
        let expectedError = NSError(
            domain: "MicroTechSensorHandshakeTests",
            code: 91,
            userInfo: [NSLocalizedDescriptionKey: "decrypt rejected"]
        )
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
            peripheralSession: fake,
            pairingKeyTimeout: 0,
            commandScheduler: nil,
            notificationDecrypter: { _, _ in throw expectedError }
        )
        sensor.delegate = observer
        try sensor.start()

        sensor.handleNotification(characteristic: MicroTechAidexProfile.f003UUID, value: encrypted)

        XCTAssertTrue(observer.logMessages.contains { log in
            log.message == "stage=packet event=received characteristic=F003 encryptedLen=\(encrypted.count) encryptedHex=\(encrypted.microTechHexadecimalString)"
        })
        XCTAssertTrue(observer.logMessages.contains { log in
            log.type == .error &&
                log.message == "stage=packet event=decrypt_failed characteristic=F003 encryptedLen=\(encrypted.count) encryptedHex=\(encrypted.microTechHexadecimalString) \(MicroTechDiagnosticLog.errorFields(expectedError))"
        })
    }

    func testNotificationLogsCompleteEncryptedAndDecryptedPackets() throws {
        let material = MicroTechAidexKeyMaterial.derive(serial: "ABC123")
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
            peripheralSession: fake,
            pairingKeyTimeout: 0
        )
        sensor.delegate = observer
        try sensor.start()

        let f002Plain = MicroTechAidexCrypto.appendingCRC(to: Data([0x10]))
        let f002Encrypted = try MicroTechAidexCrypto.encryptCfb128(
            key: material.key,
            iv: material.iv,
            plain: f002Plain
        )
        sensor.handleNotification(characteristic: MicroTechAidexProfile.f002UUID, value: f002Encrypted)

        let f003Plain = MicroTechAidexCrypto.appendingCRC(
            to: Data([0x7F]) + Data((0..<40).map(UInt8.init))
        )
        let f003Encrypted = try MicroTechAidexCrypto.encryptCfb128(
            key: material.key,
            iv: material.iv,
            plain: f003Plain
        )
        XCTAssertGreaterThan(f003Encrypted.count, 32)
        sensor.handleNotification(characteristic: MicroTechAidexProfile.f003UUID, value: f003Encrypted)

        for (characteristic, encrypted, plain) in [
            ("F002", f002Encrypted, f002Plain),
            ("F003", f003Encrypted, f003Plain),
        ] {
            XCTAssertTrue(observer.logMessages.contains { log in
                log.message == "stage=packet event=received characteristic=\(characteristic) encryptedLen=\(encrypted.count) encryptedHex=\(encrypted.microTechHexadecimalString)"
            })
            XCTAssertTrue(observer.logMessages.contains { log in
                log.message == "stage=packet event=decrypted characteristic=\(characteristic) plainLen=\(plain.count) plainHex=\(plain.microTechHexadecimalString)"
            })
        }
        XCTAssertTrue(observer.logMessages.allSatisfy { log in
            !log.message.contains("rawPrefix") &&
                !log.message.contains("hexPrefix") &&
                !log.message.contains("...")
        })
    }

    func testParserFailureKeepsCompletePlainPacket() throws {
        let material = MicroTechAidexKeyMaterial.derive(serial: "ABC123")
        let plain = MicroTechAidexCrypto.appendingCRC(to: Data([0x03]))
        let encrypted = try MicroTechAidexCrypto.encryptCfb128(
            key: material.key,
            iv: material.iv,
            plain: plain
        )
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
            peripheralSession: fake,
            pairingKeyTimeout: 0
        )
        sensor.delegate = observer
        try sensor.start()

        sensor.handleNotification(characteristic: MicroTechAidexProfile.f003UUID, value: encrypted)

        XCTAssertTrue(observer.logMessages.contains { log in
            log.type == .error &&
                log.message.contains("stage=packet event=parse_failed characteristic=F003") &&
                log.message.contains("plainLen=\(plain.count) plainHex=\(plain.microTechHexadecimalString)")
        })
    }

    func testHistoryAndActivationCommandsLogCompleteHex() throws {
        let material = MicroTechAidexKeyMaterial.derive(serial: "ABC123")
        let fake = FakeMicroTechPeripheralSession(
            deviceIdentifier: UUID(uuidString: "00000000-0000-0000-0000-000000000123")!,
            deviceName: "LinX-ABC123",
            f002Challenge: try encryptedChallenge(for: material)
        )
        let observer = ReadingObserver()
        var commandBlocks: [() -> Void] = []
        let sensor = MicroTechSensor(
            session: MicroTechAidexSession(
                remoteIdentifier: fake.deviceIdentifier,
                deviceName: fake.deviceName,
                sensorSerial: "ABC123"
            ),
            peripheralSession: fake,
            pairingKeyTimeout: 0,
            commandScheduler: { commandBlocks.append($0) }
        )
        sensor.delegate = observer

        try sensor.start()
        try sensor.startSensor(at: Date(timeIntervalSince1970: 1_700_000_000))
        for packetType in [UInt8(0x10), 0x31, 0x20, 0x35, 0x34] {
            let plain = MicroTechAidexCrypto.appendingCRC(to: Data([packetType]))
            let encrypted = try MicroTechAidexCrypto.encryptCfb128(
                key: material.key,
                iv: material.iv,
                plain: plain
            )
            sensor.handleNotification(characteristic: MicroTechAidexProfile.f002UUID, value: encrypted)
            XCTAssertFalse(commandBlocks.isEmpty)
            commandBlocks.removeFirst()()
        }
        try sensor.requestHistory(index: 60)
        XCTAssertFalse(commandBlocks.isEmpty)
        commandBlocks.removeFirst()()

        let protocolWrites = fake.calls.compactMap { call -> String? in
            guard case .write(let hex, let characteristic) = call,
                  characteristic == MicroTechAidexProfile.f002UUID.uuidString,
                  hex != "B0D893"
            else {
                return nil
            }
            return hex
        }
        XCTAssertEqual(protocolWrites.count, 6)
        for (command, hex) in zip(
            ["cmd31", "cmd20", "cmd35", "cmd34", "cmd11", "history_request"],
            protocolWrites
        ) {
            let data = try Data(microTechHexadecimalString: hex)
            XCTAssertTrue(observer.logMessages.contains { log in
                log.message == packetLog(
                    event: "send_attempted",
                    characteristic: "F002",
                    command: command,
                    data: data
                )
            })
            XCTAssertTrue(observer.logMessages.contains { log in
                log.message == packetLog(
                    event: "send_succeeded",
                    characteristic: "F002",
                    command: command,
                    data: data
                )
            })
        }
    }

    func testSendFailureLogsCompletePacketAndNSError() throws {
        let material = MicroTechAidexKeyMaterial.derive(serial: "ABC123")
        let expectedError = NSError(
            domain: "MicroTechSensorHandshakeTests",
            code: 73,
            userInfo: [NSLocalizedDescriptionKey: "write rejected"]
        )
        let fake = FakeMicroTechPeripheralSession(
            deviceIdentifier: UUID(uuidString: "00000000-0000-0000-0000-000000000123")!,
            deviceName: "LinX-ABC123",
            f002Challenge: try encryptedChallenge(for: material),
            writeError: expectedError
        )
        let observer = ReadingObserver()
        let sensor = MicroTechSensor(
            session: MicroTechAidexSession(
                remoteIdentifier: fake.deviceIdentifier,
                deviceName: fake.deviceName,
                sensorSerial: "ABC123"
            ),
            peripheralSession: fake,
            pairingKeyTimeout: 0
        )
        sensor.delegate = observer

        XCTAssertThrowsError(try sensor.start())

        XCTAssertTrue(observer.logMessages.contains { log in
            log.type == .error &&
                log.message == packetLog(
                    event: "send_failed",
                    characteristic: "F001",
                    command: "base_key",
                    data: material.key
                ) + " \(MicroTechDiagnosticLog.errorFields(expectedError))"
        })
    }

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
            peripheralSession: fake,
            pairingKeyTimeout: 0
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
            peripheralSession: fake,
            pairingKeyTimeout: 0
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

    func testConnectedSessionUsesPeripheralIdentity() throws {
        let material = MicroTechAidexKeyMaterial.derive(serial: "ABC123")
        let fake = FakeMicroTechPeripheralSession(
            deviceIdentifier: UUID(uuidString: "00000000-0000-0000-0000-000000000123")!,
            deviceName: "AiDEX-ABC123",
            f002Challenge: try encryptedChallenge(for: material)
        )
        let observer = ReadingObserver()
        let sensor = MicroTechSensor(
            session: MicroTechAidexSession(
                remoteIdentifier: UUID(uuidString: "00000000-0000-0000-0000-000000000999")!,
                deviceName: "MicroTech LinX",
                sensorSerial: "ABC123"
            ),
            peripheralSession: fake,
            pairingKeyTimeout: 0
        )
        sensor.delegate = observer

        try sensor.start()

        let connectedSession = try XCTUnwrap(observer.connectedSessions.single)
        XCTAssertEqual(connectedSession.remoteIdentifier, fake.deviceIdentifier)
        XCTAssertEqual(connectedSession.deviceName, "AiDEX-ABC123")
        XCTAssertEqual(connectedSession.sensorSerial, "ABC123")
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
            peripheralSession: fake,
            pairingKeyTimeout: 0
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

    func testF003NotificationEmitsLinxCurrentReadingFromDeviceLog() throws {
        let material = MicroTechAidexKeyMaterial.derive(serial: "ABC123")
        let plain = try Data(microTechHexadecimalString: "030100FE60545F80B303800C4500004D5B")
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
            peripheralSession: fake,
            pairingKeyTimeout: 0
        )
        sensor.delegate = observer

        try sensor.start()
        sensor.handleNotification(
            characteristic: MicroTechAidexProfile.f003UUID,
            value: encrypted,
            receivedAt: receivedAt
        )

        let reading = try XCTUnwrap(observer.readings.single)
        XCTAssertEqual(95, reading.glucoseMgdl)
        XCTAssertEqual(21600, reading.sampleNumber)
        XCTAssertEqual(-2, reading.trend)
        XCTAssertEqual(receivedAt, reading.receivedAt)
        XCTAssertEqual("ABC123", reading.sensorSerial)
        XCTAssertTrue(observer.historyPackets.isEmpty)
        XCTAssertTrue(observer.ignoredPackets.isEmpty)
        XCTAssertTrue(observer.errors.isEmpty)
    }

    func testHandshakeUsesF001PairingKeyForSessionMaterial() throws {
        let material = MicroTechAidexKeyMaterial.derive(serial: "ABC123")
        let f001PairingKey = Data((0..<16).map { UInt8(0x90 + $0) })
        let sessionKey = Data((0..<16).map { UInt8($0 + 1) })
        let challenge = try MicroTechAidexCrypto.encryptCfb128(
            key: f001PairingKey,
            iv: material.iv,
            plain: sessionKey + Data([0x00])
        )
        let fake = FakeMicroTechPeripheralSession(
            deviceIdentifier: UUID(uuidString: "00000000-0000-0000-0000-000000000123")!,
            deviceName: "LinX-ABC123",
            f002Challenge: challenge
        )
        let observer = ReadingObserver()
        let sensor = MicroTechSensor(
            session: MicroTechAidexSession(
                remoteIdentifier: fake.deviceIdentifier,
                deviceName: fake.deviceName,
                sensorSerial: "ABC123"
            ),
            peripheralSession: fake,
            pairingKeyTimeout: 0
        )
        fake.onWrite = { value, characteristic in
            guard characteristic == MicroTechAidexProfile.f001UUID, value == material.key else {
                return
            }
            sensor.handleNotification(characteristic: MicroTechAidexProfile.f001UUID, value: f001PairingKey)
        }
        sensor.delegate = observer

        try sensor.start()
        let currentPacket = try Data(microTechHexadecimalString: "010003FF2A007B00D204C409B80B0100003FC5")
        let encryptedCurrentPacket = try MicroTechAidexCrypto.encryptCfb128(
            key: sessionKey,
            iv: material.iv,
            plain: currentPacket
        )
        sensor.handleNotification(
            characteristic: MicroTechAidexProfile.f003UUID,
            value: encryptedCurrentPacket,
            receivedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        XCTAssertEqual(123, observer.readings.single?.glucoseMgdl)
        XCTAssertTrue(observer.errors.isEmpty)
    }

    func testHandshakeFailsWhenF001SubscribeSucceedsButPairingKeyIsMissing() throws {
        let material = MicroTechAidexKeyMaterial.derive(serial: "ABC123")
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
            peripheralSession: fake,
            pairingKeyTimeout: 0.01
        )
        sensor.delegate = observer

        XCTAssertThrowsError(try sensor.start()) { error in
            XCTAssertEqual(error as? MicroTechSensorError, .pairingKeyUnavailable)
        }

        XCTAssertEqual(1, fake.calls.filter { $0 == .disconnect }.count)
        XCTAssertTrue(observer.connectedSessions.isEmpty)
        XCTAssertEqual(observer.errors.single as? MicroTechSensorError, .pairingKeyUnavailable)
        XCTAssertTrue(observer.logMessages.contains { log in
            log.type == .error && log.message.contains("F001 pairing key unavailable")
        })
    }

    func testF002NotificationEmitsHistoryPacket() throws {
        let material = MicroTechAidexKeyMaterial.derive(serial: "ABC123")
        let plain = try Data(microTechHexadecimalString: "2300E8036F007000FFFFFB1A")
        let encrypted = try MicroTechAidexCrypto.encryptCfb128(key: material.key, iv: material.iv, plain: plain)
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
            peripheralSession: fake,
            pairingKeyTimeout: 0
        )
        sensor.delegate = observer

        try sensor.start()
        sensor.handleNotification(characteristic: MicroTechAidexProfile.f002UUID, value: encrypted)

        let history = try XCTUnwrap(observer.historyPackets.single)
        XCTAssertEqual(history.records.map(\.timeOffset), [1000, 1001])
        XCTAssertEqual(history.records.map(\.glucose), [111, 112])
        XCTAssertTrue(observer.errors.isEmpty)
    }

    func testMalformedF003CurrentPacketReportsInvalidPacket() throws {
        let material = MicroTechAidexKeyMaterial.derive(serial: "ABC123")
        let plain = MicroTechAidexCrypto.appendingCRC(to: Data([0x03]))
        let encrypted = try MicroTechAidexCrypto.encryptCfb128(key: material.key, iv: material.iv, plain: plain)
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
            peripheralSession: fake,
            pairingKeyTimeout: 0
        )
        sensor.delegate = observer

        try sensor.start()
        sensor.handleNotification(characteristic: MicroTechAidexProfile.f003UUID, value: encrypted)

        XCTAssertTrue(observer.readings.isEmpty)
        XCTAssertTrue(observer.historyPackets.isEmpty)
        XCTAssertTrue(observer.ignoredPackets.isEmpty)
        XCTAssertEqual(observer.errors.single as? MicroTechAidexParserError, .invalidPacket)
    }

    func testStatusPacketNotificationIsIgnoredWithoutError() throws {
        let material = MicroTechAidexKeyMaterial.derive(serial: "ABC123")
        let plain = MicroTechAidexCrypto.appendingCRC(to: Data([0x04]))
        let encrypted = try MicroTechAidexCrypto.encryptCfb128(key: material.key, iv: material.iv, plain: plain)
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
            peripheralSession: fake,
            pairingKeyTimeout: 0
        )
        sensor.delegate = observer

        try sensor.start()
        sensor.handleNotification(characteristic: MicroTechAidexProfile.f003UUID, value: encrypted)

        XCTAssertTrue(observer.readings.isEmpty)
        XCTAssertTrue(observer.historyPackets.isEmpty)
        XCTAssertEqual(observer.ignoredPackets.single?.packetType, 0x04)
        XCTAssertEqual(observer.ignoredPackets.single?.length, plain.count)
        XCTAssertTrue(observer.errors.isEmpty)
        XCTAssertFalse(observer.logMessages.contains { log in
            log.type == .error && log.message.contains("unsupported packet type=0x04")
        })
    }

    func testCmd11ActivationResponseCompletesActivationWithoutError() throws {
        let material = MicroTechAidexKeyMaterial.derive(serial: "ABC123")
        let fake = FakeMicroTechPeripheralSession(
            deviceIdentifier: UUID(uuidString: "00000000-0000-0000-0000-000000000123")!,
            deviceName: "LinX-ABC123",
            f002Challenge: try encryptedChallenge(for: material)
        )
        let observer = ReadingObserver()
        var commandBlocks: [() -> Void] = []
        let sensor = MicroTechSensor(
            session: MicroTechAidexSession(
                remoteIdentifier: fake.deviceIdentifier,
                deviceName: fake.deviceName,
                sensorSerial: "ABC123"
            ),
            peripheralSession: fake,
            pairingKeyTimeout: 0,
            commandScheduler: { commandBlocks.append($0) }
        )
        sensor.delegate = observer
        let startTime = Date(timeIntervalSince1970: 1_700_000_000)

        try sensor.start()
        try sensor.startSensor(at: startTime)
        for packetType in [UInt8(0x10), 0x31, 0x20, 0x35, 0x34] {
            let plain = MicroTechAidexCrypto.appendingCRC(to: Data([packetType]))
            let encrypted = try MicroTechAidexCrypto.encryptCfb128(key: material.key, iv: material.iv, plain: plain)
            sensor.handleNotification(characteristic: MicroTechAidexProfile.f002UUID, value: encrypted)
            if !commandBlocks.isEmpty {
                commandBlocks.removeFirst()()
            }
        }
        let cmd11Response = try Data(microTechHexadecimalString: "110160540100FE5F806200007EBD")
        let encryptedCmd11Response = try MicroTechAidexCrypto.encryptCfb128(
            key: material.key,
            iv: material.iv,
            plain: cmd11Response
        )
        sensor.handleNotification(characteristic: MicroTechAidexProfile.f002UUID, value: encryptedCmd11Response)

        let expectedCmd11 = try MicroTechAidexCommandBuilder(keyMaterial: material)
            .cmd11()
            .microTechHexadecimalString
        XCTAssertTrue(fake.calls.contains(.write(expectedCmd11, MicroTechAidexProfile.f002UUID.uuidString)))
        XCTAssertEqual(observer.activationTimes.single, startTime)
        XCTAssertTrue(observer.errors.isEmpty)
        XCTAssertTrue(observer.logMessages.contains { log in
            log.type == .receive && log.message.contains("protocol response cmd11 ack")
        })
    }

    func testActivationFollowUpCommandIsScheduledOutsideNotificationCallback() throws {
        let material = MicroTechAidexKeyMaterial.derive(serial: "ABC123")
        let fake = FakeMicroTechPeripheralSession(
            deviceIdentifier: UUID(uuidString: "00000000-0000-0000-0000-000000000123")!,
            deviceName: "LinX-ABC123",
            f002Challenge: try encryptedChallenge(for: material)
        )
        var commandBlocks: [() -> Void] = []
        let sensor = MicroTechSensor(
            session: MicroTechAidexSession(
                remoteIdentifier: fake.deviceIdentifier,
                deviceName: fake.deviceName,
                sensorSerial: "ABC123"
            ),
            peripheralSession: fake,
            pairingKeyTimeout: 0,
            commandScheduler: { commandBlocks.append($0) }
        )

        try sensor.start()
        try sensor.startSensor(at: Date(timeIntervalSince1970: 1_700_000_000))
        let callCountBeforeNotification = fake.calls.count
        let plain = MicroTechAidexCrypto.appendingCRC(to: Data([0x10]))
        let encrypted = try MicroTechAidexCrypto.encryptCfb128(key: material.key, iv: material.iv, plain: plain)

        sensor.handleNotification(characteristic: MicroTechAidexProfile.f002UUID, value: encrypted)

        XCTAssertEqual(fake.calls.count, callCountBeforeNotification)
        XCTAssertEqual(commandBlocks.count, 1)
        guard commandBlocks.count == 1 else {
            return
        }

        commandBlocks[0]()

        let expectedCmd31 = try MicroTechAidexCommandBuilder(keyMaterial: material)
            .cmd31()
            .microTechHexadecimalString
        XCTAssertEqual(fake.calls.last, .write(expectedCmd31, MicroTechAidexProfile.f002UUID.uuidString))
    }

    func testHistoryRequestIsScheduledOutsideNotificationCallback() throws {
        let material = MicroTechAidexKeyMaterial.derive(serial: "ABC123")
        let fake = FakeMicroTechPeripheralSession(
            deviceIdentifier: UUID(uuidString: "00000000-0000-0000-0000-000000000123")!,
            deviceName: "LinX-ABC123",
            f002Challenge: try encryptedChallenge(for: material)
        )
        var commandBlocks: [() -> Void] = []
        let sensor = MicroTechSensor(
            session: MicroTechAidexSession(
                remoteIdentifier: fake.deviceIdentifier,
                deviceName: fake.deviceName,
                sensorSerial: "ABC123"
            ),
            peripheralSession: fake,
            pairingKeyTimeout: 0,
            commandScheduler: { commandBlocks.append($0) }
        )

        try sensor.start()
        let callCountBeforeHistoryRequest = fake.calls.count

        try sensor.requestHistory(index: 60)

        XCTAssertEqual(fake.calls.count, callCountBeforeHistoryRequest)
        XCTAssertEqual(commandBlocks.count, 1)
        guard commandBlocks.count == 1 else {
            return
        }

        commandBlocks[0]()

        let expectedHistoryCommand = try MicroTechAidexCommandBuilder(keyMaterial: material)
            .cmd23(index: 60)
            .microTechHexadecimalString
        XCTAssertEqual(fake.calls.last, .write(expectedHistoryCommand, MicroTechAidexProfile.f002UUID.uuidString))
    }

    func testStopOnlyNotifiesDisconnectOnce() throws {
        let material = MicroTechAidexKeyMaterial.derive(serial: "ABC123")
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
            peripheralSession: fake,
            pairingKeyTimeout: 0
        )
        sensor.delegate = observer

        try sensor.start()
        sensor.stop()
        sensor.stop()

        XCTAssertEqual(1, observer.disconnectCount)
        XCTAssertEqual(1, fake.calls.filter { $0 == .disconnect }.count)
    }

    func testStartFailureDisconnectsPeripheralWithoutDisconnectNotification() throws {
        let material = MicroTechAidexKeyMaterial.derive(serial: "ABC123")
        let failurePoints: [FakeMicroTechPeripheralSession.FailurePoint] = [.subscribe, .write, .read]

        try failurePoints.forEach { failurePoint in
            let fake = FakeMicroTechPeripheralSession(
                deviceIdentifier: UUID(uuidString: "00000000-0000-0000-0000-000000000123")!,
                deviceName: "LinX-ABC123",
                f002Challenge: try encryptedChallenge(for: material),
                failurePoint: failurePoint
            )
            let observer = ReadingObserver()
            let sensor = MicroTechSensor(
                session: MicroTechAidexSession(
                    remoteIdentifier: fake.deviceIdentifier,
                    deviceName: fake.deviceName,
                    sensorSerial: "ABC123"
                ),
                peripheralSession: fake,
                pairingKeyTimeout: 0
            )
            sensor.delegate = observer

            XCTAssertThrowsError(try sensor.start()) { error in
                XCTAssertEqual(error as? MicroTechSensorHandshakeTestError, .forcedFailure)
            }

            XCTAssertEqual(1, fake.calls.filter { $0 == .disconnect }.count)
            XCTAssertTrue(observer.connectedSessions.isEmpty)
            XCTAssertEqual(0, observer.disconnectCount)
            XCTAssertEqual(1, observer.errors.count)
        }
    }

    func testDuplicateReadyCallbacksDoNotStartHandshakeTwiceAfterFailure() throws {
        let material = MicroTechAidexKeyMaterial.derive(serial: "ABC123")
        let fake = FakeMicroTechPeripheralSession(
            deviceIdentifier: UUID(uuidString: "00000000-0000-0000-0000-000000000123")!,
            deviceName: "LinX-ABC123",
            f002Challenge: try encryptedChallenge(for: material),
            failurePoint: .write
        )
        let observer = ReadingObserver()
        let sensor = MicroTechSensor(
            session: MicroTechAidexSession(
                remoteIdentifier: fake.deviceIdentifier,
                deviceName: fake.deviceName,
                sensorSerial: "ABC123"
            ),
            peripheralSession: fake,
            pairingKeyTimeout: 0
        )
        sensor.delegate = observer

        sensor.handleReadyPeripheralSession(fake)
        sensor.handleReadyPeripheralSession(fake)

        let deadline = Date(timeIntervalSinceNow: 1)
        while Date() < deadline, fake.calls.filter({ $0 == .disconnect }).isEmpty {
            Thread.sleep(forTimeInterval: 0.01)
        }
        Thread.sleep(forTimeInterval: 0.05)

        XCTAssertEqual(1, fake.calls.filter { $0 == .disconnect }.count)
        XCTAssertEqual(1, fake.calls.filter { $0 == .subscribe(MicroTechAidexProfile.f002UUID.uuidString) }.count)
        XCTAssertEqual(1, observer.errors.count)
    }

    func testStartIsIdempotentAfterSuccessfulHandshake() throws {
        let material = MicroTechAidexKeyMaterial.derive(serial: "ABC123")
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
            peripheralSession: fake,
            pairingKeyTimeout: 0
        )
        sensor.delegate = observer

        try sensor.start()
        let firstStartCalls = fake.calls
        try sensor.start()

        XCTAssertEqual(firstStartCalls, fake.calls)
        XCTAssertEqual(1, observer.connectedSessions.count)
    }

    func testReadyCallbackAfterSuccessfulHandshakeRestartsHandshakeForConnectedRefresh() throws {
        let material = MicroTechAidexKeyMaterial.derive(serial: "ABC123")
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
            peripheralSession: fake,
            pairingKeyTimeout: 0
        )
        sensor.delegate = observer

        try sensor.start()
        sensor.handleReadyPeripheralSession(fake)

        let deadline = Date(timeIntervalSinceNow: 1)
        while Date() < deadline, observer.connectedSessions.count < 2 {
            Thread.sleep(forTimeInterval: 0.01)
        }

        XCTAssertEqual(2, fake.calls.filter { $0 == .subscribe(MicroTechAidexProfile.f002UUID.uuidString) }.count)
        XCTAssertEqual(2, fake.calls.filter { $0 == .subscribe(MicroTechAidexProfile.f003UUID.uuidString) }.count)
        XCTAssertEqual(2, observer.connectedSessions.count)
    }

    private func encryptedChallenge(for material: MicroTechAidexKeyMaterial) throws -> Data {
        try MicroTechAidexCrypto.encryptCfb128(key: material.key, iv: material.iv, plain: material.key)
    }

    private func packetLog(event: String, characteristic: String, command: String, data: Data) -> String {
        "stage=packet event=\(event) characteristic=\(characteristic) command=\(command) len=\(data.count) hex=\(data.microTechHexadecimalString)"
    }
}

enum MicroTechSensorHandshakeTestError: Error, Equatable {
    case forcedFailure
}

final class FakeMicroTechPeripheralSession: MicroTechPeripheralSession {
    enum Call: Equatable {
        case subscribe(String)
        case write(String, String)
        case read(String)
        case disconnect
    }

    enum FailurePoint {
        case subscribe
        case write
        case read
    }

    let deviceIdentifier: UUID
    let deviceName: String
    private let f002Challenge: Data
    private let failurePoint: FailurePoint?
    private let writeError: Error?
    private let subscriptionFailures: [CBUUID]
    var onWrite: ((Data, CBUUID) -> Void)?
    private(set) var calls: [Call] = []

    init(
        deviceIdentifier: UUID,
        deviceName: String,
        f002Challenge: Data,
        failurePoint: FailurePoint? = nil,
        writeError: Error? = nil,
        subscriptionFailures: [CBUUID] = []
    ) {
        self.deviceIdentifier = deviceIdentifier
        self.deviceName = deviceName
        self.f002Challenge = f002Challenge
        self.failurePoint = failurePoint
        self.writeError = writeError
        self.subscriptionFailures = subscriptionFailures
    }

    func subscribe(_ characteristic: CBUUID) throws {
        calls.append(.subscribe(characteristic.uuidString))
        if subscriptionFailures.contains(characteristic) {
            throw MicroTechSensorHandshakeTestError.forcedFailure
        }
        if failurePoint == .subscribe {
            throw MicroTechSensorHandshakeTestError.forcedFailure
        }
    }

    func write(_ value: Data, to characteristic: CBUUID) throws {
        calls.append(.write(value.microTechHexadecimalString, characteristic.uuidString))
        onWrite?(value, characteristic)
        if let writeError {
            throw writeError
        }
        if failurePoint == .write {
            throw MicroTechSensorHandshakeTestError.forcedFailure
        }
    }

    func read(_ characteristic: CBUUID) throws -> Data {
        calls.append(.read(characteristic.uuidString))
        if failurePoint == .read {
            throw MicroTechSensorHandshakeTestError.forcedFailure
        }
        return f002Challenge
    }

    func disconnect() {
        calls.append(.disconnect)
    }
}

final class ReadingObserver: MicroTechSensorDelegate {
    struct IgnoredPacket: Equatable {
        let packetType: UInt8
        let length: Int
        let rawHex: String
    }

    private(set) var readings: [MicroTechGlucoseReading] = []
    private(set) var historyPackets: [MicroTechAidexHistoryPacket] = []
    private(set) var ignoredPackets: [IgnoredPacket] = []
    private(set) var logMessages: [(message: String, type: MicroTechSensorLogType)] = []
    private(set) var errors: [Error] = []
    private(set) var connectedSessions: [MicroTechAidexSession] = []
    private(set) var activationTimes: [Date] = []
    private(set) var disconnectCount = 0
    private(set) var packetNotifications: [(characteristic: CBUUID, receivedAt: Date)] = []
    var notificationEvents: [String] = []

    func microTechSensor(
        _ sensor: MicroTechSensor,
        didReceivePacketFor characteristic: CBUUID,
        receivedAt: Date
    ) {
        packetNotifications.append((characteristic: characteristic, receivedAt: receivedAt))
        let name: String
        switch characteristic {
        case MicroTechAidexProfile.f001UUID:
            name = "F001"
        case MicroTechAidexProfile.f002UUID:
            name = "F002"
        case MicroTechAidexProfile.f003UUID:
            name = "F003"
        default:
            name = characteristic.uuidString
        }
        notificationEvents.append("packet:\(name)")
    }

    func microTechSensor(_ sensor: MicroTechSensor, didRead reading: MicroTechGlucoseReading) {
        readings.append(reading)
    }

    func microTechSensor(_ sensor: MicroTechSensor, didReadHistory history: MicroTechAidexHistoryPacket) {
        historyPackets.append(history)
    }

    func microTechSensor(_ sensor: MicroTechSensor, didActivateAt activationTime: Date) {
        activationTimes.append(activationTime)
    }

    func microTechSensor(_ sensor: MicroTechSensor, didIgnorePacketType packetType: UInt8, length: Int, hexPrefix rawHex: String) {
        ignoredPackets.append(IgnoredPacket(packetType: packetType, length: length, rawHex: rawHex))
    }

    func microTechSensor(_ sensor: MicroTechSensor, didLog message: String, type: MicroTechSensorLogType) {
        logMessages.append((message: message, type: type))
        if message.contains("stage=handshake event=pairing_key_received characteristic=F001") {
            notificationEvents.append("pairing-store")
        }
    }

    func microTechSensor(_ sensor: MicroTechSensor, didError error: Error) {
        errors.append(error)
        notificationEvents.append("error")
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
