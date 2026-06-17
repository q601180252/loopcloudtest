import CoreBluetooth
import Foundation
import os.log

public enum MicroTechBluetoothLogType {
    case connection
    case error
}

public enum MicroTechBluetoothManagerError: Error, Equatable, CustomStringConvertible {
    case connectTimeout(UUID)
    case connectFailed(UUID, String?)
    case scanTimeout(UUID?)
    case bluetoothUnavailable(Int)

    public var description: String {
        switch self {
        case .connectTimeout(let identifier):
            return "connection timed out for \(identifier)"
        case .connectFailed(let identifier, let underlyingDescription):
            if let underlyingDescription, !underlyingDescription.isEmpty {
                return "connection failed for \(identifier): \(underlyingDescription)"
            }
            return "connection failed for \(identifier)"
        case .scanTimeout(let identifier):
            if let identifier {
                return "scan timed out for \(identifier)"
            }
            return "scan timed out"
        case .bluetoothUnavailable(let state):
            return "Bluetooth unavailable state=\(state)"
        }
    }
}

final class MicroTechConnectionTimeoutController {
    private let timeout: TimeInterval
    private let queue: DispatchQueue
    private var workItems: [UUID: DispatchWorkItem] = [:]

    init(timeout: TimeInterval, queue: DispatchQueue) {
        self.timeout = timeout
        self.queue = queue
    }

    func schedule(identifier: UUID, handler: @escaping (UUID) -> Void) {
        cancel(identifier: identifier)
        guard timeout > 0 else {
            return
        }

        let workItem = DispatchWorkItem { [weak self] in
            self?.workItems[identifier] = nil
            handler(identifier)
        }
        workItems[identifier] = workItem
        queue.asyncAfter(deadline: .now() + timeout, execute: workItem)
    }

    func cancel(identifier: UUID) {
        workItems.removeValue(forKey: identifier)?.cancel()
    }
}

protocol MicroTechBluetoothManaging: AnyObject {
    var delegate: MicroTechBluetoothManagerDelegate? { get set }
    var logHandler: ((String, MicroTechBluetoothLogType) -> Void)? { get set }
    var isScanning: Bool { get }
    var isConnected: Bool { get }

    func scan(remoteIdentifier: UUID?)
    func refreshConnectedPeripheral()
    func disconnect()
    func forgetPeripheral()
}

extension MicroTechBluetoothManaging {
    func refreshConnectedPeripheral() {}
}

public protocol MicroTechBluetoothManagerDelegate: AnyObject {
    func microTechBluetoothManager(_ manager: MicroTechBluetoothManager, shouldConnectToDeviceName deviceName: String, identifier: UUID) -> Bool
    func microTechBluetoothManager(_ manager: MicroTechBluetoothManager, didReady peripheralSession: MicroTechPeripheralSession)
    func microTechBluetoothManager(_ manager: MicroTechBluetoothManager, didReceive value: Data, for characteristic: CBUUID, session: MicroTechPeripheralSession)
    func microTechBluetoothManager(_ manager: MicroTechBluetoothManager, didDisconnect session: MicroTechPeripheralSession)
    func microTechBluetoothManager(_ manager: MicroTechBluetoothManager, didFailWith error: Error)
}

public final class MicroTechBluetoothManager: NSObject {
    enum SavedPeripheralSource: String {
        case coreBluetoothRestore = "CoreBluetooth restore"
        case retrievePeripherals
    }

    public weak var delegate: MicroTechBluetoothManagerDelegate?
    public var logHandler: ((String, MicroTechBluetoothLogType) -> Void)?
    public static let defaultConnectionTimeout: TimeInterval = 15
    public static let defaultScanTimeout: TimeInterval = 30
    static let restoreIdentifier = "com.loopkit.MicroTechCGM"

    public private(set) var activeRemoteIdentifier: UUID?
    private let log = OSLog(category: "MicroTechBluetoothManager")

    private let managerQueue = DispatchQueue(label: "com.loopkit.MicroTechCGM.bluetoothManager")
    private let managerQueueSpecificKey = DispatchSpecificKey<Bool>()
    private lazy var connectionTimeouts = MicroTechConnectionTimeoutController(
        timeout: Self.defaultConnectionTimeout,
        queue: managerQueue
    )
    private var scanTimeoutWorkItem: DispatchWorkItem?
    private var centralManager: CBCentralManager!
    private var managedPeripherals: [UUID: MicroTechPeripheralManager] = [:]
    private var restoredPeripherals: [UUID: CBPeripheral] = [:]
    private var configuringPeripheralIDs: Set<UUID> = []
    private var activePeripheralManager: MicroTechPeripheralManager? {
        didSet {
            activeRemoteIdentifier = activePeripheralManager?.deviceIdentifier
        }
    }

    public override init() {
        super.init()

        managerQueue.setSpecific(key: managerQueueSpecificKey, value: true)
        managerQueue.sync {
            centralManager = CBCentralManager(
                delegate: self,
                queue: managerQueue,
                options: [CBCentralManagerOptionRestoreIdentifierKey: Self.restoreIdentifier]
            )
        }
    }

    public var isScanning: Bool {
        syncOnManagerQueue {
            centralManager.isScanning
        }
    }

    public var isConnected: Bool {
        syncOnManagerQueue {
            activePeripheralManager?.isConnected == true
        }
    }

    public func scan(remoteIdentifier: UUID? = nil) {
        managerQueue.async {
            self.activeRemoteIdentifier = remoteIdentifier
            self.logBluetooth("scan requested, activeRemoteIdentifier \(String(describing: self.activeRemoteIdentifier))")
            self.scanIfReady()
        }
    }

    public func refreshConnectedPeripheral() {
        managerQueue.async {
            guard let manager = self.activePeripheralManager, manager.isConnected else {
                self.scanIfReady()
                return
            }

            self.logBluetooth("refreshing connected peripheral \(manager.deviceIdentifier), name \(manager.deviceName)")
            self.configureAndNotifyReady(manager)
        }
    }

    public func stopScanning() {
        managerQueue.async {
            self.stopScanningOnQueue()
        }
    }

    public func disconnect() {
        managerQueue.async {
            self.stopScanningOnQueue()
            if let manager = self.activePeripheralManager {
                self.removeManager(manager, cancelConnection: true)
            }
        }
    }

    public func forgetPeripheral() {
        managerQueue.async {
            self.activePeripheralManager = nil
            self.restoredPeripherals.removeAll()
        }
    }

    private func scanIfReady() {
        switch centralManager.state {
        case .poweredOn:
            break
        case .unknown, .resetting:
            logBluetooth("scan deferred because central state is \(centralManager.state.rawValue)")
            return
        case .unsupported, .unauthorized, .poweredOff:
            let error = MicroTechBluetoothManagerError.bluetoothUnavailable(centralManager.state.rawValue)
            logBluetooth("scan failed because \(error)", type: .error)
            delegate?.microTechBluetoothManager(self, didFailWith: error)
            return
        @unknown default:
            let error = MicroTechBluetoothManagerError.bluetoothUnavailable(centralManager.state.rawValue)
            logBluetooth("scan failed because \(error)", type: .error)
            delegate?.microTechBluetoothManager(self, didFailWith: error)
            return
        }

        if let identifier = activeRemoteIdentifier,
           let peripheral = restoredPeripherals[identifier]
        {
            logBluetooth(Self.savedPeripheralLogMessage(identifier: identifier, name: peripheral.name, source: .coreBluetoothRestore))
            connectIfNeeded(peripheral, advertisedName: peripheral.name)
            return
        }

        if let identifier = activeRemoteIdentifier,
           let peripheral = centralManager.retrievePeripherals(withIdentifiers: [identifier]).first
        {
            logBluetooth(Self.savedPeripheralLogMessage(identifier: identifier, name: peripheral.name, source: .retrievePeripherals))
            connectIfNeeded(peripheral, advertisedName: peripheral.name)
            return
        }

        for peripheral in centralManager.retrieveConnectedPeripherals(withServices: [MicroTechAidexProfile.serviceUUID]) {
            logBluetooth("found connected peripheral \(peripheral.identifier), name \(String(describing: peripheral.name))")
            connectIfNeeded(peripheral, advertisedName: peripheral.name)
            if activePeripheralManager != nil {
                return
            }
        }

        guard activePeripheralManager == nil else {
            return
        }

        centralManager.registerForConnectionEvents(options: [
            CBConnectionEventMatchingOption.serviceUUIDs: [MicroTechAidexProfile.serviceUUID],
        ])
        logBluetooth("scanning for MicroTech service \(MicroTechAidexProfile.serviceUUID.uuidString)")
        centralManager.scanForPeripherals(withServices: [MicroTechAidexProfile.serviceUUID], options: nil)
        scheduleScanTimeout(remoteIdentifier: activeRemoteIdentifier)
    }

    private func stopScanningOnQueue() {
        cancelScanTimeout()
        if centralManager.isScanning {
            logBluetooth("stopping scan")
            centralManager.stopScan()
        }
    }

    private func syncOnManagerQueue<Value>(_ work: () -> Value) -> Value {
        if DispatchQueue.getSpecific(key: managerQueueSpecificKey) == true {
            return work()
        }

        return managerQueue.sync(execute: work)
    }

    private func connectIfNeeded(_ peripheral: CBPeripheral, advertisedName: String?) {
        let deviceName = advertisedName ?? peripheral.name ?? ""
        let shouldConnectByIdentifier = activeRemoteIdentifier == peripheral.identifier

        if !shouldConnectByIdentifier,
           delegate?.microTechBluetoothManager(self, shouldConnectToDeviceName: deviceName, identifier: peripheral.identifier) != true
        {
            logBluetooth("delegate rejected peripheral \(peripheral.identifier), advertisedName \(deviceName)")
            return
        }

        let manager = managedPeripherals[peripheral.identifier] ?? MicroTechPeripheralManager(
            peripheral: peripheral,
            centralManager: centralManager,
            advertisedName: deviceName
        )
        manager.updateAdvertisedName(deviceName)
        manager.delegate = self
        managedPeripherals[peripheral.identifier] = manager
        activePeripheralManager = manager
        cancelScanTimeout()

        switch peripheral.state {
        case .connected:
            cancelConnectionTimeout(for: manager.deviceIdentifier)
            logBluetooth("configuring connected peripheral \(peripheral.identifier), name \(manager.deviceName)")
            configureAndNotifyReady(manager)
        case .disconnected:
            logBluetooth("connecting peripheral \(peripheral.identifier), name \(manager.deviceName)")
            scheduleConnectionTimeout(for: manager)
            centralManager.connect(peripheral)
        case .connecting:
            logBluetooth("peripheral already connecting \(peripheral.identifier), name \(manager.deviceName)")
            scheduleConnectionTimeoutIfNeeded(for: manager, state: peripheral.state)
        case .disconnecting:
            logBluetooth("peripheral is disconnecting \(peripheral.identifier), name \(manager.deviceName)")
            scheduleConnectionTimeoutIfNeeded(for: manager, state: peripheral.state)
        @unknown default:
            logBluetooth("peripheral unknown state \(peripheral.identifier), name \(manager.deviceName)")
            scheduleConnectionTimeout(for: manager)
        }
    }

    private func configureAndNotifyReady(_ manager: MicroTechPeripheralManager) {
        let identifier = manager.deviceIdentifier
        cancelConnectionTimeout(for: identifier)
        guard configuringPeripheralIDs.insert(identifier).inserted else {
            return
        }

        DispatchQueue.global(qos: .utility).async {
            do {
                try manager.configure()
                self.managerQueue.async {
                    self.configuringPeripheralIDs.remove(identifier)
                    guard self.managedPeripherals[identifier] === manager else {
                        return
                    }
                    self.stopScanningOnQueue()
                    self.logBluetooth("peripheral ready \(identifier), name \(manager.deviceName)")
                    self.delegate?.microTechBluetoothManager(self, didReady: manager)
                }
            } catch {
                self.managerQueue.async {
                    self.configuringPeripheralIDs.remove(identifier)
                    self.logBluetooth("peripheral configure failed \(identifier), name \(manager.deviceName), error \(String(describing: error))", type: .error)
                    self.removeManager(manager, cancelConnection: true)
                    self.delegate?.microTechBluetoothManager(self, didFailWith: error)
                    self.scanIfReady()
                }
            }
        }
    }

    private func removeManager(_ manager: MicroTechPeripheralManager, cancelConnection: Bool) {
        let identifier = manager.deviceIdentifier
        cancelConnectionTimeout(for: identifier)
        if cancelConnection {
            manager.disconnect()
        }
        manager.delegate = nil
        managedPeripherals.removeValue(forKey: identifier)
        configuringPeripheralIDs.remove(identifier)
        if activePeripheralManager === manager {
            activePeripheralManager = nil
        }
    }

    private func logBluetooth(_ message: String, type: MicroTechBluetoothLogType = .connection) {
        os_log("%{public}@", log: log, type: .default, message)
        logHandler?(message, type)
    }

    private func scheduleConnectionTimeout(for manager: MicroTechPeripheralManager) {
        let identifier = manager.deviceIdentifier
        connectionTimeouts.schedule(identifier: identifier) { [weak self] identifier in
            self?.handleConnectionTimeout(identifier: identifier)
        }
    }

    private func scheduleConnectionTimeoutIfNeeded(for manager: MicroTechPeripheralManager, state: CBPeripheralState) {
        guard Self.shouldScheduleConnectionTimeout(for: state) else {
            return
        }
        scheduleConnectionTimeout(for: manager)
    }

    static func shouldScheduleConnectionTimeout(for state: CBPeripheralState) -> Bool {
        switch state {
        case .connected:
            return false
        case .disconnected, .connecting, .disconnecting:
            return true
        @unknown default:
            return true
        }
    }

    static func savedPeripheralLogMessage(identifier: UUID, name: String?, source: SavedPeripheralSource) -> String {
        "retrieved saved peripheral \(identifier) from \(source.rawValue), name \(String(describing: name))"
    }

    private func cancelConnectionTimeout(for identifier: UUID) {
        connectionTimeouts.cancel(identifier: identifier)
    }

    private func handleConnectionTimeout(identifier: UUID) {
        guard let manager = managedPeripherals[identifier],
              activePeripheralManager === manager,
              !manager.isConnected else
        {
            return
        }

        let error = MicroTechBluetoothManagerError.connectTimeout(identifier)
        logBluetooth("connect timed out peripheral \(identifier), name \(manager.deviceName)", type: .error)
        removeManager(manager, cancelConnection: true)
        delegate?.microTechBluetoothManager(self, didFailWith: error)
        scanIfReady()
    }

    private func scheduleScanTimeout(remoteIdentifier: UUID?) {
        cancelScanTimeout()
        guard Self.defaultScanTimeout > 0 else {
            return
        }

        let workItem = DispatchWorkItem { [weak self] in
            self?.handleScanTimeout(remoteIdentifier: remoteIdentifier)
        }
        scanTimeoutWorkItem = workItem
        managerQueue.asyncAfter(deadline: .now() + Self.defaultScanTimeout, execute: workItem)
    }

    private func cancelScanTimeout() {
        scanTimeoutWorkItem?.cancel()
        scanTimeoutWorkItem = nil
    }

    private func handleScanTimeout(remoteIdentifier: UUID?) {
        scanTimeoutWorkItem = nil
        guard centralManager.isScanning, activePeripheralManager == nil else {
            return
        }

        let error = MicroTechBluetoothManagerError.scanTimeout(remoteIdentifier)
        logBluetooth("scan timed out, remoteIdentifier \(String(describing: remoteIdentifier))", type: .error)
        stopScanningOnQueue()
        delegate?.microTechBluetoothManager(self, didFailWith: error)
    }
}

extension MicroTechBluetoothManager: MicroTechBluetoothManaging {
}

extension MicroTechBluetoothManager: CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard central.state == .poweredOn else {
            logBluetooth("central state changed to \(central.state.rawValue), stopping scan")
            stopScanningOnQueue()
            return
        }
        logBluetooth("central powered on")
        scanIfReady()
    }

    public func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        guard let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] else {
            logBluetooth("willRestoreState without restored peripherals")
            return
        }
        let identifiers = peripherals.map(\.identifier.uuidString).joined(separator: ",")
        logBluetooth("willRestoreState restored peripherals count=\(peripherals.count) identifiers=\(identifiers)")
        for peripheral in peripherals {
            restoredPeripherals[peripheral.identifier] = peripheral
            connectIfNeeded(peripheral, advertisedName: peripheral.name)
        }
    }

    public func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        logBluetooth("didDiscover peripheral \(peripheral.identifier), advertisedName \(String(describing: advertisedName)), peripheralName \(String(describing: peripheral.name)), rssi \(RSSI)")
        connectIfNeeded(peripheral, advertisedName: advertisedName)
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard let manager = managedPeripherals[peripheral.identifier] else {
            return
        }

        cancelConnectionTimeout(for: peripheral.identifier)
        logBluetooth("didConnect peripheral \(peripheral.identifier), name \(manager.deviceName)")
        configureAndNotifyReady(manager)
    }

    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        let manager = managedPeripherals[peripheral.identifier]
        if let manager {
            removeManager(manager, cancelConnection: false)
        }
        if let error {
            logBluetooth("didFailToConnect peripheral \(peripheral.identifier), error \(String(describing: error))", type: .error)
        } else {
            logBluetooth("didFailToConnect peripheral \(peripheral.identifier) without error", type: .error)
        }
        delegate?.microTechBluetoothManager(
            self,
            didFailWith: MicroTechBluetoothManagerError.connectFailed(peripheral.identifier, error.map { String(describing: $0) })
        )
        scanIfReady()
    }

    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard let manager = managedPeripherals[peripheral.identifier] else {
            return
        }
        if let error {
            logBluetooth("didDisconnect peripheral \(peripheral.identifier), error \(String(describing: error))", type: .error)
        } else {
            logBluetooth("didDisconnect peripheral \(peripheral.identifier)")
        }
        manager.didDisconnect(error: error)
        removeManager(manager, cancelConnection: false)
        scanIfReady()
    }

    public func centralManager(_ central: CBCentralManager, connectionEventDidOccur event: CBConnectionEvent, for peripheral: CBPeripheral) {
        logBluetooth("connection event \(Self.name(for: event)) peripheral \(peripheral.identifier), name \(String(describing: peripheral.name))")
        switch event {
        case .peerConnected:
            connectIfNeeded(peripheral, advertisedName: peripheral.name)
        case .peerDisconnected:
            if let manager = managedPeripherals[peripheral.identifier] {
                manager.didDisconnect(error: nil)
                removeManager(manager, cancelConnection: false)
            }
            scanIfReady()
        @unknown default:
            scanIfReady()
        }
    }
}

extension MicroTechBluetoothManager: MicroTechPeripheralManagerDelegate {
    public func microTechPeripheralManager(_ manager: MicroTechPeripheralManager, didUpdateValue value: Data, for characteristic: CBUUID) {
        delegate?.microTechBluetoothManager(self, didReceive: value, for: characteristic, session: manager)
    }

    public func microTechPeripheralManager(_ manager: MicroTechPeripheralManager, didDisconnectWith error: Error?) {
        delegate?.microTechBluetoothManager(self, didDisconnect: manager)
        if let error {
            logBluetooth("peripheral manager disconnected with error \(String(describing: error))", type: .error)
            delegate?.microTechBluetoothManager(self, didFailWith: error)
        }
        removeManager(manager, cancelConnection: false)
        scanIfReady()
    }
}

private extension MicroTechBluetoothManager {
    static func name(for event: CBConnectionEvent) -> String {
        switch event {
        case .peerConnected:
            return "peerConnected"
        case .peerDisconnected:
            return "peerDisconnected"
        @unknown default:
            return "unknown"
        }
    }
}
