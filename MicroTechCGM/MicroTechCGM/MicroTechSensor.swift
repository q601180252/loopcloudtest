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
    func microTechSensor(_ sensor: MicroTechSensor, didIgnorePacketType packetType: UInt8, length: Int, hexPrefix: String)
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
    private let startSchedulingLock = NSLock()
    private let pairingKeyCondition = NSCondition()
    private var isStarted = false
    private var startScheduled = false
    private var activeSession: MicroTechAidexSession?
    private var commandBuilder: MicroTechAidexCommandBuilder?
    private var pendingPairingKey: Data?
    private var pendingStartTime: Date?
    private var cmd10ResponseSeen = false
    private var autoStartSequenceActive = false

    public init(
        session: MicroTechAidexSession,
        peripheralSession: MicroTechPeripheralSession,
        pairingKeyTimeout: TimeInterval = 15,
        commandScheduler: ((@escaping () -> Void) -> Void)? = nil
    ) {
        let handshakeQueue = DispatchQueue(label: "com.loopkit.MicroTechCGM.sensorHandshake")
        self.session = session
        self.peripheralSession = peripheralSession
        self.pairingKeyTimeout = pairingKeyTimeout
        self.handshakeQueue = handshakeQueue
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
            logSensor("sending F001 base key len=\(baseMaterial.key.count)", type: .send)
            try peripheralSession.write(baseMaterial.key, to: MicroTechAidexProfile.f001UUID)
            logSensor("sent F001 base key len=\(baseMaterial.key.count)", type: .send)
            let pairingKeyResult = try waitForPairingKey(
                fallback: baseMaterial.key,
                requirePairingKey: f001NotificationsSubscribed && pairingKeyTimeout > 0
            )
            let pairingKey = pairingKeyResult.key
            logSensor(
                "pairing key source=\(pairingKeyResult.source) len=\(pairingKey.count)",
                type: .connection
            )
            logSensor("sending F001 pairing response len=\(pairingKey.count)", type: .send)
            try peripheralSession.write(pairingKey, to: MicroTechAidexProfile.f001UUID)
            logSensor("sent F001 pairing response len=\(pairingKey.count)", type: .send)

            logSensor("reading F002 challenge", type: .send)
            let challenge = try peripheralSession.read(MicroTechAidexProfile.f002UUID)
            logSensor("read F002 challenge len=\(challenge.count)", type: .receive)
            let sessionMaterial = try MicroTechAidexKeyMaterial.deriveSessionMaterial(
                baseMaterial: baseMaterial,
                encryptedChallenge: challenge,
                pairingKey: pairingKey
            )
            logSensor("derived session material from F002 challenge", type: .connection)
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
            try peripheralSession.write(cmd10, to: MicroTechAidexProfile.f002UUID)
            logSensor("sent cmd10 to F002 len=\(cmd10.count)", type: .send)
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
        logSensor(
            "notification \(Self.name(for: characteristic)) encryptedLen=\(value.count)",
            type: .receive
        )
        if characteristic == MicroTechAidexProfile.f001UUID {
            storePairingKey(value)
            return
        }
        let isF002 = characteristic == MicroTechAidexProfile.f002UUID
        let isF003 = characteristic == MicroTechAidexProfile.f003UUID
        guard isF002 || isF003 else { return }
        guard let commandBuilder, let activeSession else {
            logSensor("notification ignored because session is inactive", type: .error)
            delegate?.microTechSensor(self, didError: MicroTechSensorError.inactiveSession)
            return
        }

        do {
            let plain = try commandBuilder.decryptNotification(value)
            logSensor(
                "notification \(Self.name(for: characteristic)) decrypted type=\(Self.packetTypeDescription(plain)) plainLen=\(plain.count) rawPrefix=\(Self.hexPrefix(plain))",
                type: .receive
            )
            if handleProtocolResponse(plain) {
                return
            }
            do {
                switch try MicroTechAidexParser.parse(plain) {
                case .current(let packet):
                    logSensor(
                        "parsed current packetType=\(Self.packetTypeDescription(packet.rawBytes)) sample=\(packet.timeOffset) value=\(packet.glucose) quality=\(packet.quality) status=\(packet.status) trend=\(packet.trend) rawPrefix=\(Self.hexPrefix(packet.rawBytes))",
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
                        hexPrefix: Data(plain.prefix(32)).microTechHexadecimalString
                    )
                } else {
                    logSensor(
                        "unexpected unsupported packet type=\(String(format: "0x%02X", packetType)) plainLen=\(plain.count) rawPrefix=\(Self.hexPrefix(plain))",
                        type: .error
                    )
                    delegate?.microTechSensor(self, didError: MicroTechAidexParserError.unsupportedPacket(packetType))
                }
            }
        } catch {
            logSensor(
                "notification \(Self.name(for: characteristic)) failed: \(Self.describe(error)) encryptedLen=\(value.count)",
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
            try sensor.peripheralSession.write(command, to: MicroTechAidexProfile.f002UUID)
            sensor.logSensor("sent history request index=\(index) len=\(command.count)", type: .send)
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
        pairingKeyCondition.unlock()
    }

    private func storePairingKey(_ value: Data) {
        do {
            let key = try MicroTechAidexKeyMaterial.normalizeKey(value)
            pairingKeyCondition.lock()
            pendingPairingKey = key
            pairingKeyCondition.signal()
            pairingKeyCondition.unlock()
            logSensor("received F001 pairing key len=\(value.count) normalizedLen=\(key.count)", type: .receive)
        } catch {
            logSensor("F001 pairing key rejected: \(Self.describe(error)) len=\(value.count)", type: .error)
            delegate?.microTechSensor(self, didError: error)
        }
    }

    private func waitForPairingKey(fallback: Data, requirePairingKey: Bool) throws -> (key: Data, source: String) {
        pairingKeyCondition.lock()
        defer { pairingKeyCondition.unlock() }

        if let pendingPairingKey {
            return (pendingPairingKey, "f001")
        }
        guard requirePairingKey else {
            return (fallback, "fallback")
        }
        guard pairingKeyTimeout > 0 else {
            return (fallback, "fallback")
        }

        let timeoutDate = Date(timeIntervalSinceNow: pairingKeyTimeout)
        while pendingPairingKey == nil && pairingKeyCondition.wait(until: timeoutDate) {
        }
        if let pendingPairingKey {
            return (pendingPairingKey, "f001")
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
        try peripheralSession.write(command, to: MicroTechAidexProfile.f002UUID)
        logSensor("sent activation cmd31 len=\(command.count)", type: .send)
    }

    private func sendAutoStartTime() throws {
        guard let pendingStartTime, let commandBuilder else {
            return
        }
        let command = try commandBuilder.cmd20(dateTimeBytes: Self.dateTimeBytes(for: pendingStartTime))
        try peripheralSession.write(command, to: MicroTechAidexProfile.f002UUID)
        logSensor("sent activation cmd20 start=\(pendingStartTime) len=\(command.count)", type: .send)
    }

    private func sendAutoStartCommand35() throws {
        guard pendingStartTime != nil, let commandBuilder else {
            return
        }
        let command = try commandBuilder.cmd35()
        try peripheralSession.write(command, to: MicroTechAidexProfile.f002UUID)
        logSensor("sent activation cmd35 len=\(command.count)", type: .send)
    }

    private func sendAutoStartCommand34() throws {
        guard pendingStartTime != nil, let commandBuilder else {
            return
        }
        let command = try commandBuilder.cmd34()
        try peripheralSession.write(command, to: MicroTechAidexProfile.f002UUID)
        logSensor("sent activation cmd34 len=\(command.count)", type: .send)
    }

    private func sendAutoStartCommand11() throws {
        guard pendingStartTime != nil, let commandBuilder else {
            return
        }
        let command = try commandBuilder.cmd11()
        try peripheralSession.write(command, to: MicroTechAidexProfile.f002UUID)
        logSensor("sent activation cmd11 len=\(command.count)", type: .send)
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

    private static func hexPrefix(_ data: Data) -> String {
        Data(data.prefix(32)).microTechHexadecimalString
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
