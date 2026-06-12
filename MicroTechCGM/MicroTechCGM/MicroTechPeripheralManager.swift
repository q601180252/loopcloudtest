import CoreBluetooth
import Foundation

public protocol MicroTechPeripheralSession: AnyObject {
    var deviceIdentifier: UUID { get }
    var deviceName: String { get }

    func subscribe(_ characteristic: CBUUID) throws
    func write(_ value: Data, to characteristic: CBUUID) throws
    func read(_ characteristic: CBUUID) throws -> Data
    func disconnect()
}

public protocol MicroTechPeripheralManagerDelegate: AnyObject {
    func microTechPeripheralManager(_ manager: MicroTechPeripheralManager, didUpdateValue value: Data, for characteristic: CBUUID)
    func microTechPeripheralManager(_ manager: MicroTechPeripheralManager, didDisconnectWith error: Error?)
}

public enum MicroTechPeripheralManagerError: Error, Equatable {
    case notConnected
    case timeout
    case unknownService
    case unknownCharacteristic(CBUUID)
    case noValue(CBUUID)
    case invalidCommand
}

public final class MicroTechPeripheralManager: NSObject, MicroTechPeripheralSession {
    public weak var delegate: MicroTechPeripheralManagerDelegate?

    public var deviceIdentifier: UUID {
        peripheral.identifier
    }

    public var deviceName: String {
        peripheral.name ?? "MicroTech LinX"
    }

    private let peripheral: CBPeripheral
    private weak var centralManager: CBCentralManager?
    private let condition = NSCondition()
    private let timeout: TimeInterval
    private var characteristics: [CBUUID: CBCharacteristic] = [:]
    private var pendingCommand: Command?
    private var pendingError: Error?

    public init(peripheral: CBPeripheral, centralManager: CBCentralManager, timeout: TimeInterval = 2) {
        self.peripheral = peripheral
        self.centralManager = centralManager
        self.timeout = timeout

        super.init()

        peripheral.delegate = self
    }

    public func configure() throws {
        if peripheral.services?.contains(where: { $0.uuid == MicroTechAidexProfile.serviceUUID }) != true {
            try run(.discoverServices) {
                peripheral.discoverServices([MicroTechAidexProfile.serviceUUID])
            }
        }

        guard let service = peripheral.services?.first(where: { $0.uuid == MicroTechAidexProfile.serviceUUID }) else {
            throw MicroTechPeripheralManagerError.unknownService
        }

        let requiredCharacteristics = [
            MicroTechAidexProfile.f001UUID,
            MicroTechAidexProfile.f002UUID,
            MicroTechAidexProfile.f003UUID,
        ]

        if service.characteristics?.contains(where: { requiredCharacteristics.contains($0.uuid) }) != true ||
            service.characteristics?.count ?? 0 < requiredCharacteristics.count
        {
            try run(.discoverCharacteristics(service.uuid)) {
                peripheral.discoverCharacteristics(requiredCharacteristics, for: service)
            }
        }

        characteristics = Dictionary(
            uniqueKeysWithValues: (service.characteristics ?? [])
                .filter { requiredCharacteristics.contains($0.uuid) }
                .map { ($0.uuid, $0) }
        )

        for characteristic in requiredCharacteristics where characteristics[characteristic] == nil {
            throw MicroTechPeripheralManagerError.unknownCharacteristic(characteristic)
        }
    }

    public func subscribe(_ characteristic: CBUUID) throws {
        let cbCharacteristic = try requiredCharacteristic(characteristic)
        try run(.notification(characteristic, enabled: true)) {
            peripheral.setNotifyValue(true, for: cbCharacteristic)
        }
    }

    public func write(_ value: Data, to characteristic: CBUUID) throws {
        let cbCharacteristic = try requiredCharacteristic(characteristic)
        let writeType: CBCharacteristicWriteType = cbCharacteristic.properties.contains(.write) ? .withResponse : .withoutResponse

        if writeType == .withResponse {
            try run(.write(characteristic)) {
                peripheral.writeValue(value, for: cbCharacteristic, type: writeType)
            }
        } else {
            peripheral.writeValue(value, for: cbCharacteristic, type: writeType)
        }
    }

    public func read(_ characteristic: CBUUID) throws -> Data {
        let cbCharacteristic = try requiredCharacteristic(characteristic)
        try run(.read(characteristic)) {
            peripheral.readValue(for: cbCharacteristic)
        }
        guard let value = cbCharacteristic.value else {
            throw MicroTechPeripheralManagerError.noValue(characteristic)
        }
        return value
    }

    public func disconnect() {
        guard peripheral.state != .disconnected else {
            return
        }
        centralManager?.cancelPeripheralConnection(peripheral)
    }

    func didDisconnect(error: Error?) {
        delegate?.microTechPeripheralManager(self, didDisconnectWith: error)
    }

    private func requiredCharacteristic(_ uuid: CBUUID) throws -> CBCharacteristic {
        guard let characteristic = characteristics[uuid] else {
            throw MicroTechPeripheralManagerError.unknownCharacteristic(uuid)
        }
        return characteristic
    }

    private func run(_ command: Command, action: () -> Void) throws {
        guard peripheral.state == .connected else {
            throw MicroTechPeripheralManagerError.notConnected
        }

        condition.lock()
        defer {
            pendingCommand = nil
            pendingError = nil
            condition.unlock()
        }

        guard pendingCommand == nil else {
            throw MicroTechPeripheralManagerError.invalidCommand
        }

        pendingCommand = command
        action()

        let completed = condition.wait(until: Date(timeIntervalSinceNow: timeout))
        guard completed else {
            throw MicroTechPeripheralManagerError.timeout
        }
        if let pendingError {
            throw pendingError
        }
    }
}

private extension MicroTechPeripheralManager {
    enum Command: Equatable {
        case discoverServices
        case discoverCharacteristics(CBUUID)
        case notification(CBUUID, enabled: Bool)
        case read(CBUUID)
        case write(CBUUID)
    }

    func complete(_ command: Command, error: Error?) {
        condition.lock()
        if pendingCommand == command {
            pendingError = error
            condition.signal()
        }
        condition.unlock()
    }
}

extension MicroTechPeripheralManager: CBPeripheralDelegate {
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        complete(.discoverServices, error: error)
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        complete(.discoverCharacteristics(service.uuid), error: error)
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        complete(.notification(characteristic.uuid, enabled: characteristic.isNotifying), error: error)
    }

    public func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        complete(.write(characteristic.uuid), error: error)
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        condition.lock()
        let completesRead = pendingCommand == .read(characteristic.uuid)
        if completesRead {
            pendingError = error
            condition.signal()
        }
        condition.unlock()

        guard !completesRead, error == nil, let value = characteristic.value else {
            return
        }
        delegate?.microTechPeripheralManager(self, didUpdateValue: value, for: characteristic.uuid)
    }
}
