import CoreBluetooth
import Foundation

public enum MicroTechSensorLogType {
    case connection
    case send
    case receive
    case error
}

public protocol MicroTechSensorDelegate: AnyObject {
    func microTechSensor(_ sensor: MicroTechSensor, didRead reading: MicroTechGlucoseReading)
    func microTechSensor(_ sensor: MicroTechSensor, didReadHistory history: MicroTechAidexHistoryPacket)
    func microTechSensor(_ sensor: MicroTechSensor, didActivateAt activationTime: Date)
    func microTechSensor(_ sensor: MicroTechSensor, didIgnorePacketType packetType: UInt8, length: Int, hexPrefix rawHex: String)
    func microTechSensor(_ sensor: MicroTechSensor, didLog message: String, type: MicroTechSensorLogType)
    func microTechSensor(_ sensor: MicroTechSensor, didError error: Error)
    func microTechSensorDidConnect(_ sensor: MicroTechSensor, session: MicroTechAidexSession)
    func microTechSensorDidDisconnect(_ sensor: MicroTechSensor)
}

public struct MicroTechAidexSession: Equatable {
    public let remoteIdentifier: UUID
    public let deviceName: String
    public let sensorSerial: String

    public init(remoteIdentifier: UUID, deviceName: String, sensorSerial: String) {
        self.remoteIdentifier = remoteIdentifier
        self.deviceName = deviceName
        self.sensorSerial = sensorSerial
    }
}

public enum MicroTechSensorError: Error, Equatable {
    case inactiveSession
    case pairingKeyUnavailable
}

public final class MicroTechSensor {
    public weak var delegate: MicroTechSensorDelegate?

    private let session: MicroTechAidexSession
    private var peripheralSession: MicroTechPeripheralSession
    private let pairingKeyTimeout: TimeInterval
    private let handshakeQueue: DispatchQueue
    private let commandScheduler: (@escaping () -> Void) -> Void
    private let notificationDecrypter: (MicroTechAidexCommandBuilder, Data) throws -> Data
    private let startSchedulingLock = NSLock()
    private let pairingKeyCondition = NSCondition()
    private var isStarted = false
    private var startScheduled = false
    private var activeSession: MicroTechAidexSession?
    private var commandBuilder: MicroTechAidexCommandBuilder?
    private var pendingPairingKey: Data?
    private var pendingRawPairingKey: Data?
    private var pendingStartTime: Date?
    private var cmd10ResponseSeen = false
    private var autoStartSequenceActive = false

    public convenience init(
        session: MicroTechAidexSession,
        peripheralSession: MicroTechPeripheralSession,
        pairingKeyTimeout: TimeInterval = 15,
        commandScheduler: ((@escaping () -> Void) -> Void)? = nil
    ) {
        self.init(
            session: session,
            peripheralSession: peripheralSession,
            pairingKeyTimeout: pairingKeyTimeout,
            commandScheduler: commandScheduler,
            notificationDecrypter: { builder, encrypted in
                try builder.decryptNotification(encrypted)
            }
        )
    }

    init(
        session: MicroTechAidexSession,
        peripheralSession: MicroTechPeripheralSession,
        pairingKeyTimeout: TimeInterval,
        commandScheduler: ((@escaping () -> Void) -> Void)?,
        notificationDecrypter: @escaping (MicroTechAidexCommandBuilder, Data) throws -> Data
    ) {
        let handshakeQueue = DispatchQueue(label: "com.loopkit.MicroTechCGM.sensorHandshake")
        self.session = session
        self.peripheralSession = peripheralSession
        self.pairingKeyTimeout = pairingKeyTimeout
        self.handshakeQueue = handshakeQueue
        self.notificationDecrypter = notificationDecrypter
        self.commandScheduler = commandScheduler ?? { command in
            handshakeQueue.async(execute: command)
        }
    }

    public func start() throws {
        guard !(isStarted && commandBuilder != nil && activeSession != nil) else {
            logSensor("handshake skipped because session is already active", type: .connection)
            return
        }

        do {
            resetPairingKey()
            cmd10ResponseSeen = false
            autoStartSequenceActive = false
            let baseMaterial = MicroTechAidexKeyMaterial.derive(serial: session.sensorSerial)
            logSensor(
                "handshake start device=\(peripheralSession.deviceName) identifier=\(peripheralSession.deviceIdentifier) serial=\(session.sensorSerial)",
                type: .connection
            )
            logSensor(
                "stage=handshake event=base_material serial=\(session.sensorSerial) baseKey=\(baseMaterial.key.microTechHexadecimalString) baseIV=\(baseMaterial.iv.microTechHexadecimalString)",
                type: .connection
            )

            try peripheralSession.subscribe(MicroTechAidexProfile.f002UUID)
            logSensor("subscribed F002 notifications", type: .connection)
            var f001NotificationsSubscribed = false
            do {
                try peripheralSession.subscribe(MicroTechAidexProfile.f001UUID)
                f001NotificationsSubscribed = true
                logSensor("subscribed F001 notifications", type: .connection)
            } catch {
                logSensor("F001 notification subscribe skipped: \(Self.describe(error))", type: .connection)
            }
            try writePacket(baseMaterial.key, to: MicroTechAidexProfile.f001UUID, command: "base_key")
            let pairingKeyResult = try waitForPairingKey(
                fallback: baseMaterial.key,
                requirePairingKey: f001NotificationsSubscribed && pairingKeyTimeout > 0
            )
            let pairingKey = pairingKeyResult.key
            if pairingKeyResult.source == "fallback" {
                logSensor(
                    "stage=handshake event=pairing_key source=fallback rawPairingKey=\(pairingKeyResult.rawKey.microTechHexadecimalString) pairingKey=\(pairingKey.microTechHexadecimalString)",
                    type: .connection
                )
            }
            try writePacket(pairingKey, to: MicroTechAidexProfile.f001UUID, command: "pairing_response")

            logSensor("reading F002 challenge", type: .send)
            let challenge = try peripheralSession.read(MicroTechAidexProfile.f002UUID)
            logSensor(
                "stage=handshake event=challenge characteristic=F002 len=\(challenge.count) challengeHex=\(challenge.microTechHexadecimalString)",
                type: .receive
            )
            let sessionMaterial = try MicroTechAidexKeyMaterial.deriveSessionMaterial(
                baseMaterial: baseMaterial,
                encryptedChallenge: challenge,
                pairingKey: pairingKey
            )
            logSensor(
                "stage=handshake event=session_material sessionKey=\(sessionMaterial.key.microTechHexadecimalString) sessionIV=\(sessionMaterial.iv.microTechHexadecimalString)",
                type: .connection
            )
            let builder = MicroTechAidexCommandBuilder(keyMaterial: sessionMaterial)
            let connectedSession = MicroTechAidexSession(
                remoteIdentifier: peripheralSession.deviceIdentifier,
                deviceName: peripheralSession.deviceName,
                sensorSerial: session.sensorSerial
            )
            commandBuilder = builder
            activeSession = connectedSession
            isStarted = true
            try peripheralSession.subscribe(MicroTechAidexProfile.f003UUID)
            logSensor("subscribed F003 notifications", type: .connection)
            let cmd10 = try builder.cmd10()
            try writePacket(cmd10, to: MicroTechAidexProfile.f002UUID, command: "cmd10")
            logSensor("handshake ready, waiting for F002/F003 data", type: .connection)
            delegate?.microTechSensorDidConnect(self, session: connectedSession)
        } catch {
            logSensor("handshake failed: \(Self.describe(error))", type: .error)
            isStarted = false
            commandBuilder = nil
            activeSession = nil
            peripheralSession.disconnect()
            delegate?.microTechSensor(self, didError: error)
            throw error
        }
    }

    public func handleNotification(characteristic: CBUUID, value: Data, receivedAt: Date = Date()) {
        if characteristic == MicroTechAidexProfile.f001UUID {
            storePairingKey(value)
            return
        }
        let isF002 = characteristic == MicroTechAidexProfile.f002UUID
        let isF003 = characteristic == MicroTechAidexProfile.f003UUID
        guard isF002 || isF003 else { return }
        let characteristicName = Self.name(for: characteristic)
        logSensor(
            "stage=packet event=received characteristic=\(characteristicName) encryptedLen=\(value.count) encryptedHex=\(value.microTechHexadecimalString)",
            type: .receive
        )
        guard let commandBuilder, let activeSession else {
            logSensor("notification ignored because session is inactive", type: .error)
            delegate?.microTechSensor(self, didError: MicroTechSensorError.inactiveSession)
            return
        }

        let plain: Data
        do {
            plain = try notificationDecrypter(commandBuilder, value)
        } catch {
            logSensor(
                "stage=packet event=decrypt_failed characteristic=\(characteristicName) encryptedLen=\(value.count) encryptedHex=\(value.microTechHexadecimalString) \(MicroTechDiagnosticLog.errorFields(error))",
                type: .error
            )
            delegate?.microTechSensor(self, didError: error)
            return
        }

        logSensor(
            "stage=packet event=decrypted characteristic=\(characteristicName) plainLen=\(plain.count) plainHex=\(plain.microTechHexadecimalString)",
            type: .receive
        )
        if handleProtocolResponse(plain) {
            return
        }
        do {
            switch try MicroTechAidexParser.parse(plain) {
            case .current(let packet):
                logSensor(
                    "parsed current packetType=\(Self.packetTypeDescription(packet.rawBytes)) sample=\(packet.timeOffset) value=\(packet.glucose) quality=\(packet.quality) status=\(packet.status) trend=\(packet.trend) rawHex=\(packet.rawBytes.microTechHexadecimalString)",
                    type: .receive
                )
                delegate?.microTechSensor(
                    self,
                    didRead: MicroTechGlucoseReading(
                        current: packet,
                        sensorSerial: activeSession.sensorSerial,
                        receivedAt: receivedAt
                    )
                )
            case .history(let packet):
                let first = packet.records.first?.timeOffset
                let last = packet.records.last?.timeOffset
                logSensor(
                    "parsed history start=\(packet.startTimeOffset) records=\(packet.records.count) first=\(String(describing: first)) last=\(String(describing: last))",
                    type: .receive
                )
                delegate?.microTechSensor(self, didReadHistory: packet)
            case .startTime:
                break
            }
        } catch MicroTechAidexParserError.unsupportedPacket(let packetType) {
            if Self.shouldIgnoreUnsupportedPacket(packetType) {
                delegate?.microTechSensor(
                    self,
                    didIgnorePacketType: packetType,
                    length: plain.count,
                    hexPrefix: plain.microTechHexadecimalString
                )
            } else {
                let error = MicroTechAidexParserError.unsupportedPacket(packetType)
                logSensor(
                    "stage=packet event=parse_failed characteristic=\(characteristicName) plainLen=\(plain.count) plainHex=\(plain.microTechHexadecimalString) \(MicroTechDiagnosticLog.errorFields(error))",
                    type: .error
                )
                delegate?.microTechSensor(self, didError: error)
            }
        } catch {
            logSensor(
                "stage=packet event=parse_failed characteristic=\(characteristicName) plainLen=\(plain.count) plainHex=\(plain.microTechHexadecimalString) \(MicroTechDiagnosticLog.errorFields(error))",
                type: .error
            )
            delegate?.microTechSensor(self, didError: error)
        }
    }

    public func startSensor(at startTime: Date) throws {
        pendingStartTime = startTime
        guard isStarted, commandBuilder != nil else {
            logSensor("activation queued but handshake is not ready", type: .connection)
            return
        }
        guard cmd10ResponseSeen else {
            logSensor("activation queued, waiting for cmd10 response", type: .connection)
            return
        }
        try sendAutoStartCommand31()
    }

    public func requestHistory(index: Int) throws {
        guard let commandBuilder else {
            logSensor("history request index=\(index) failed because session is inactive", type: .error)
            throw MicroTechSensorError.inactiveSession
        }
        let command = try commandBuilder.cmd23(index: index)
        scheduleProtocolCommand("history request index=\(index)") { sensor in
            guard sensor.commandBuilder != nil else {
                throw MicroTechSensorError.inactiveSession
            }
            try sensor.writePacket(command, to: MicroTechAidexProfile.f002UUID, command: "history_request")
        }
    }

    public func stop() {
        guard isStarted else {
            return
        }
        logSensor("sensor stop requested", type: .connection)
        isStarted = false
        peripheralSession.disconnect()
        commandBuilder = nil
        activeSession = nil
        pendingStartTime = nil
        cmd10ResponseSeen = false
        autoStartSequenceActive = false
        delegate?.microTechSensorDidDisconnect(self)
    }

    private func resetPairingKey() {
        pairingKeyCondition.lock()
        pendingPairingKey = nil
        pendingRawPairingKey = nil
        pairingKeyCondition.unlock()
    }

    private func storePairingKey(_ value: Data) {
        logSensor(
            "stage=handshake event=pairing_key_received characteristic=F001 len=\(value.count) rawPairingKey=\(value.microTechHexadecimalString)",
            type: .receive
        )
        do {
            let key = try MicroTechAidexKeyMaterial.normalizeKey(value)
            pairingKeyCondition.lock()
            pendingPairingKey = key
            pendingRawPairingKey = value
            pairingKeyCondition.signal()
            pairingKeyCondition.unlock()
            logSensor(
                "stage=handshake event=pairing_key source=f001 rawPairingKey=\(value.microTechHexadecimalString) pairingKey=\(key.microTechHexadecimalString)",
                type: .receive
            )
        } catch {
            logSensor(
                "stage=handshake event=pairing_key_failed source=f001 rawPairingKey=\(value.microTechHexadecimalString) \(MicroTechDiagnosticLog.errorFields(error))",
                type: .error
            )
            delegate?.microTechSensor(self, didError: error)
        }
    }

    private func waitForPairingKey(fallback: Data, requirePairingKey: Bool) throws -> (key: Data, rawKey: Data, source: String) {
        pairingKeyCondition.lock()
        defer { pairingKeyCondition.unlock() }

        if let pendingPairingKey, let pendingRawPairingKey {
            return (pendingPairingKey, pendingRawPairingKey, "f001")
        }
        guard requirePairingKey else {
            return (fallback, fallback, "fallback")
        }
        guard pairingKeyTimeout > 0 else {
            return (fallback, fallback, "fallback")
        }

        let timeoutDate = Date(timeIntervalSinceNow: pairingKeyTimeout)
        while pendingPairingKey == nil && pairingKeyCondition.wait(until: timeoutDate) {
        }
        if let pendingPairingKey, let pendingRawPairingKey {
            return (pendingPairingKey, pendingRawPairingKey, "f001")
        }
        logSensor("F001 pairing key unavailable after \(pairingKeyTimeout)s", type: .error)
        throw MicroTechSensorError.pairingKeyUnavailable
    }

    private func handleProtocolResponse(_ plain: Data) -> Bool {
        guard let packetType = plain.first else {
            return false
        }

        if packetType == 0x21 {
            let activationTime = parseActivationTime(from: plain) ?? pendingStartTime
            if let activationTime {
                delegate?.microTechSensor(self, didActivateAt: activationTime)
            }
            logSensor("protocol response start time activation=\(String(describing: activationTime))", type: .receive)
            pendingStartTime = nil
            autoStartSequenceActive = false
            return true
        }

        guard MicroTechAidexCrypto.hasValidTrailingCRC(plain) else {
            return false
        }

        switch packetType {
        case 0x10:
            cmd10ResponseSeen = true
            logSensor("protocol response cmd10 ack", type: .receive)
            if pendingStartTime != nil {
                scheduleProtocolCommand("activation cmd31") { sensor in
                    try sensor.sendAutoStartCommand31()
                }
            }
            return true
        case 0x31:
            logSensor("protocol response cmd31 ack", type: .receive)
            scheduleProtocolCommand("activation cmd20") { sensor in
                try sensor.sendAutoStartTime()
            }
            return true
        case 0x20:
            logSensor("protocol response cmd20 ack", type: .receive)
            scheduleProtocolCommand("activation cmd35") { sensor in
                try sensor.sendAutoStartCommand35()
            }
            return true
        case 0x35:
            logSensor("protocol response cmd35 ack", type: .receive)
            scheduleProtocolCommand("activation cmd34") { sensor in
                try sensor.sendAutoStartCommand34()
            }
            return true
        case 0x34:
            logSensor("protocol response cmd34 ack", type: .receive)
            scheduleProtocolCommand("activation cmd11") { sensor in
                try sensor.sendAutoStartCommand11()
            }
            return true
        case 0x11:
            let activationTime = parseActivationTime(from: plain) ?? pendingStartTime
            if let activationTime {
                delegate?.microTechSensor(self, didActivateAt: activationTime)
            }
            logSensor("protocol response cmd11 ack activation=\(String(describing: activationTime))", type: .receive)
            pendingStartTime = nil
            autoStartSequenceActive = false
            return true
        default:
            return false
        }
    }

    private func scheduleProtocolCommand(
        _ name: String,
        command: @escaping (MicroTechSensor) throws -> Void
    ) {
        commandScheduler { [weak self] in
            guard let self else {
                return
            }
            do {
                try command(self)
            } catch {
                logSensor("\(name) failed: \(Self.describe(error))", type: .error)
                delegate?.microTechSensor(self, didError: error)
            }
        }
    }

    private func parseActivationTime(from plain: Data) -> Date? {
        guard case .startTime(let packet) = try? MicroTechAidexParser.parse(plain) else {
            return nil
        }
        return packet.timestamp
    }

    private func sendAutoStartCommand31() throws {
        guard pendingStartTime != nil, !autoStartSequenceActive, let commandBuilder else {
            return
        }
        autoStartSequenceActive = true
        let command = try commandBuilder.cmd31()
        try writePacket(command, to: MicroTechAidexProfile.f002UUID, command: "cmd31")
    }

    private func sendAutoStartTime() throws {
        guard let pendingStartTime, let commandBuilder else {
            return
        }
        let command = try commandBuilder.cmd20(dateTimeBytes: Self.dateTimeBytes(for: pendingStartTime))
        try writePacket(command, to: MicroTechAidexProfile.f002UUID, command: "cmd20")
    }

    private func sendAutoStartCommand35() throws {
        guard pendingStartTime != nil, let commandBuilder else {
            return
        }
        let command = try commandBuilder.cmd35()
        try writePacket(command, to: MicroTechAidexProfile.f002UUID, command: "cmd35")
    }

    private func sendAutoStartCommand34() throws {
        guard pendingStartTime != nil, let commandBuilder else {
            return
        }
        let command = try commandBuilder.cmd34()
        try writePacket(command, to: MicroTechAidexProfile.f002UUID, command: "cmd34")
    }

    private func sendAutoStartCommand11() throws {
        guard pendingStartTime != nil, let commandBuilder else {
            return
        }
        let command = try commandBuilder.cmd11()
        try writePacket(command, to: MicroTechAidexProfile.f002UUID, command: "cmd11")
    }

    private func writePacket(_ value: Data, to characteristic: CBUUID, command: String) throws {
        let characteristicName = Self.name(for: characteristic)
        let fields = "characteristic=\(characteristicName) command=\(command) len=\(value.count) hex=\(value.microTechHexadecimalString)"
        logSensor("stage=packet event=send_attempted \(fields)", type: .send)
        do {
            try peripheralSession.write(value, to: characteristic)
            logSensor("stage=packet event=send_succeeded \(fields)", type: .send)
        } catch {
            logSensor(
                "stage=packet event=send_failed \(fields) \(MicroTechDiagnosticLog.errorFields(error))",
                type: .error
            )
            throw error
        }
    }

    private static func dateTimeBytes(for date: Date) -> Data {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let year = components.year ?? 2000
        let quarterHours = TimeZone.current.secondsFromGMT(for: date) / 900
        return Data([
            UInt8(year & 0xFF),
            UInt8((year >> 8) & 0xFF),
            UInt8(components.month ?? 1),
            UInt8(components.day ?? 1),
            UInt8(components.hour ?? 0),
            UInt8(components.minute ?? 0),
            UInt8(components.second ?? 0),
            UInt8(truncatingIfNeeded: quarterHours),
            0x00,
        ])
    }

    private func logSensor(_ message: String, type: MicroTechSensorLogType) {
        delegate?.microTechSensor(self, didLog: message, type: type)
    }

    private func scheduleStart(with peripheralSession: MicroTechPeripheralSession, forceRestart: Bool = false) {
        startSchedulingLock.lock()
        guard !startScheduled else {
            startSchedulingLock.unlock()
            logSensor("handshake skipped because start is already queued", type: .connection)
            return
        }
        self.peripheralSession = peripheralSession
        startScheduled = true
        startSchedulingLock.unlock()

        handshakeQueue.async {
            defer {
                self.startSchedulingLock.lock()
                self.startScheduled = false
                self.startSchedulingLock.unlock()
            }
            if forceRestart {
                self.isStarted = false
                self.commandBuilder = nil
                self.activeSession = nil
            }
            do {
                try self.start()
            } catch {
            }
        }
    }

    func handleReadyPeripheralSession(_ peripheralSession: MicroTechPeripheralSession) {
        scheduleStart(with: peripheralSession, forceRestart: true)
    }

    private static func name(for characteristic: CBUUID) -> String {
        switch characteristic {
        case MicroTechAidexProfile.f001UUID:
            return "F001"
        case MicroTechAidexProfile.f002UUID:
            return "F002"
        case MicroTechAidexProfile.f003UUID:
            return "F003"
        default:
            return characteristic.uuidString
        }
    }

    private static func packetTypeDescription(_ data: Data) -> String {
        guard let packetType = data.first else {
            return "empty"
        }
        return String(format: "0x%02X", packetType)
    }

    private static func shouldIgnoreUnsupportedPacket(_ packetType: UInt8) -> Bool {
        packetType == 0x03 || packetType == 0x04
    }

    private static func describe(_ error: Error) -> String {
        String(describing: error)
    }
}

extension MicroTechSensor: MicroTechBluetoothManagerDelegate {
    public func microTechBluetoothManager(_ manager: MicroTechBluetoothManager, shouldConnectToDeviceName deviceName: String, identifier: UUID) -> Bool {
        if identifier == session.remoteIdentifier || deviceName == session.deviceName {
            return true
        }

        let advertisedSerial = MicroTechAidexKeyMaterial.derive(deviceName: deviceName).sensorSerial
        return advertisedSerial.localizedCaseInsensitiveCompare(session.sensorSerial) == .orderedSame
    }

    public func microTechBluetoothManager(_ manager: MicroTechBluetoothManager, didReady peripheralSession: MicroTechPeripheralSession) {
        handleReadyPeripheralSession(peripheralSession)
    }

    public func microTechBluetoothManager(_ manager: MicroTechBluetoothManager, didReceive value: Data, for characteristic: CBUUID, session: MicroTechPeripheralSession) {
        handleNotification(characteristic: characteristic, value: value)
    }

    public func microTechBluetoothManager(_ manager: MicroTechBluetoothManager, didDisconnect session: MicroTechPeripheralSession) {
        stop()
    }

    public func microTechBluetoothManager(_ manager: MicroTechBluetoothManager, didFailWith error: Error) {
        delegate?.microTechSensor(self, didError: error)
    }
}
