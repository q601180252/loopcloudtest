import CoreBluetooth
import Foundation

public protocol MicroTechSensorDelegate: AnyObject {
    func microTechSensor(_ sensor: MicroTechSensor, didRead reading: MicroTechGlucoseReading)
    func microTechSensor(_ sensor: MicroTechSensor, didReadHistory history: MicroTechAidexHistoryPacket)
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
}

public final class MicroTechSensor {
    public weak var delegate: MicroTechSensorDelegate?

    private let session: MicroTechAidexSession
    private var peripheralSession: MicroTechPeripheralSession
    private var activeSession: MicroTechAidexSession?
    private var commandBuilder: MicroTechAidexCommandBuilder?

    public init(session: MicroTechAidexSession, peripheralSession: MicroTechPeripheralSession) {
        self.session = session
        self.peripheralSession = peripheralSession
    }

    public func start() throws {
        do {
            let baseMaterial = MicroTechAidexKeyMaterial.derive(deviceName: session.deviceName)
            let pairingKey = baseMaterial.key

            try peripheralSession.subscribe(MicroTechAidexProfile.f002UUID)
            try peripheralSession.subscribe(MicroTechAidexProfile.f001UUID)
            try peripheralSession.write(baseMaterial.key, to: MicroTechAidexProfile.f001UUID)
            try peripheralSession.write(pairingKey, to: MicroTechAidexProfile.f001UUID)

            let challenge = try peripheralSession.read(MicroTechAidexProfile.f002UUID)
            let sessionMaterial = try MicroTechAidexKeyMaterial.deriveSessionMaterial(
                baseMaterial: baseMaterial,
                encryptedChallenge: challenge,
                pairingKey: pairingKey
            )
            let builder = MicroTechAidexCommandBuilder(keyMaterial: sessionMaterial)
            try peripheralSession.subscribe(MicroTechAidexProfile.f003UUID)
            try peripheralSession.write(builder.cmd10(), to: MicroTechAidexProfile.f002UUID)

            commandBuilder = builder
            activeSession = MicroTechAidexSession(
                remoteIdentifier: session.remoteIdentifier,
                deviceName: session.deviceName,
                sensorSerial: session.sensorSerial
            )
            delegate?.microTechSensorDidConnect(self, session: session)
        } catch {
            delegate?.microTechSensor(self, didError: error)
            throw error
        }
    }

    public func handleNotification(characteristic: CBUUID, value: Data, receivedAt: Date = Date()) {
        guard characteristic == MicroTechAidexProfile.f003UUID else {
            return
        }
        guard let commandBuilder, let activeSession else {
            delegate?.microTechSensor(self, didError: MicroTechSensorError.inactiveSession)
            return
        }

        do {
            let plain = try commandBuilder.decryptNotification(value)
            switch try MicroTechAidexParser.parse(plain) {
            case .current(let packet):
                delegate?.microTechSensor(
                    self,
                    didRead: MicroTechGlucoseReading(
                        current: packet,
                        sensorSerial: activeSession.sensorSerial,
                        receivedAt: receivedAt
                    )
                )
            case .history(let packet):
                delegate?.microTechSensor(self, didReadHistory: packet)
            case .startTime:
                break
            }
        } catch {
            delegate?.microTechSensor(self, didError: error)
        }
    }

    public func stop() {
        peripheralSession.disconnect()
        commandBuilder = nil
        activeSession = nil
        delegate?.microTechSensorDidDisconnect(self)
    }
}

extension MicroTechSensor: MicroTechBluetoothManagerDelegate {
    public func microTechBluetoothManager(_ manager: MicroTechBluetoothManager, shouldConnectToDeviceName deviceName: String, identifier: UUID) -> Bool {
        identifier == session.remoteIdentifier || deviceName == session.deviceName
    }

    public func microTechBluetoothManager(_ manager: MicroTechBluetoothManager, didReady peripheralSession: MicroTechPeripheralSession) {
        self.peripheralSession = peripheralSession
        do {
            try start()
        } catch {
            delegate?.microTechSensor(self, didError: error)
        }
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
