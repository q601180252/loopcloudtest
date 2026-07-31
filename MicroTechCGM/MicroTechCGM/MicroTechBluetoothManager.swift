import CoreBluetooth
import Foundation
import os.log

public enum MicroTechBluetoothLogType {
    case connection
    case send
    case receive
    case error
}

public enum MicroTechBluetoothManagerError: Error, Equatable, CustomStringConvertible {
    case connectTimeout(UUID)
    case connectFailed(UUID, String?)
    case configureTimeout(UUID)
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
        case .configureTimeout(let identifier):
            return "configuration timed out for \(identifier)"
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

enum MicroTechDisconnectCallbackResult: Equatable {
    case managedPeripheral
    case expectedCancellation
    case missingPeripheralManager
}

enum MicroTechBroadcastScanPhase: Equatable {
    case filtered
    case unfiltered
}

final class MicroTechDisconnectCallbackState {
    private let lock = NSLock()
    private var expectedCancellationIdentifiers: Set<UUID> = []

    func expectCancellation(identifier: UUID) {
        lock.lock()
        expectedCancellationIdentifiers.insert(identifier)
        lock.unlock()
    }

    @discardableResult
    func handleConnectionEnd(
        callback: String,
        identifier: UUID,
        error: Error?,
        managerPresent: Bool,
        log: (String, MicroTechBluetoothLogType) -> Void
    ) -> MicroTechDisconnectCallbackResult {
        let result: MicroTechDisconnectCallbackResult
        lock.lock()
        if expectedCancellationIdentifiers.remove(identifier) != nil {
            result = .expectedCancellation
        } else if managerPresent {
            result = .managedPeripheral
        } else {
            result = .missingPeripheralManager
        }
        lock.unlock()

        switch result {
        case .expectedCancellation:
            log(
                MicroTechBluetoothManager.connectionLogMessage(
                    event: "disconnected",
                    identifier: identifier,
                    error: error
                ),
                .connection
            )
        case .managedPeripheral:
            if callback == "didDisconnectPeripheral" {
                log(
                    MicroTechBluetoothManager.connectionLogMessage(
                        event: "disconnected",
                        identifier: identifier,
                        error: error
                    ),
                    error == nil ? .connection : .error
                )
            }
        case .missingPeripheralManager:
            log(
                MicroTechBluetoothManager.missingPeripheralManagerLogMessage(
                    callback: callback,
                    identifier: identifier
                ),
                .error
            )
        }
        return result
    }
}

protocol MicroTechBluetoothManaging: AnyObject {
    var delegate: MicroTechBluetoothManagerDelegate? { get set }
    var logHandler: ((String, MicroTechBluetoothLogType) -> Void)? { get set }
    var isScanning: Bool { get }
    var isConnected: Bool { get }

    func configureConnectionMode(_ mode: MicroTechCGMConnectionMode)
    func scan(remoteIdentifier: UUID?)
    func scanForBroadcast(remoteIdentifier: UUID?)
    func refreshConnectedPeripheral()
    func disconnect()
    func forgetPeripheral()
}

extension MicroTechBluetoothManaging {
    func configureConnectionMode(_ mode: MicroTechCGMConnectionMode) {}
    func scanForBroadcast(remoteIdentifier: UUID?) {
        scan(remoteIdentifier: remoteIdentifier)
    }
    func refreshConnectedPeripheral() {}
}

public struct MicroTechBroadcastAdvertisement {
    public let identifier: UUID
    public let localName: String?
    public let peripheralName: String?
    public let advertisementData: [String: Any]
    public let rssi: NSNumber
    public let discoveredAt: Date

    public init(
        identifier: UUID,
        localName: String?,
        peripheralName: String?,
        advertisementData: [String: Any],
        rssi: NSNumber,
        discoveredAt: Date
    ) {
        self.identifier = identifier
        self.localName = localName
        self.peripheralName = peripheralName
        self.advertisementData = advertisementData
        self.rssi = rssi
        self.discoveredAt = discoveredAt
    }

    public var deviceName: String? {
        localName ?? peripheralName
    }
}

public protocol MicroTechBluetoothManagerDelegate: AnyObject {
    func microTechBluetoothManager(_ manager: MicroTechBluetoothManager, shouldConnectToDeviceName deviceName: String, identifier: UUID) -> Bool
    func microTechBluetoothManager(_ manager: MicroTechBluetoothManager, didReady peripheralSession: MicroTechPeripheralSession)
    func microTechBluetoothManager(_ manager: MicroTechBluetoothManager, didReceive value: Data, for characteristic: CBUUID, session: MicroTechPeripheralSession)
    func microTechBluetoothManager(_ manager: MicroTechBluetoothManager, didDisconnect session: MicroTechPeripheralSession)
    func microTechBluetoothManager(_ manager: MicroTechBluetoothManager, didDiscoverBroadcast advertisement: MicroTechBroadcastAdvertisement)
    func microTechBluetoothManager(_ manager: MicroTechBluetoothManager, didFailWith error: Error)
}

public extension MicroTechBluetoothManagerDelegate {
    func microTechBluetoothManager(_ manager: MicroTechBluetoothManager, didDiscoverBroadcast advertisement: MicroTechBroadcastAdvertisement) {}
}

public final class MicroTechBluetoothManager: NSObject {
    enum SavedPeripheralSource: String {
        case coreBluetoothRestore = "CoreBluetooth restore"
        case retrievePeripherals
    }

    public weak var delegate: MicroTechBluetoothManagerDelegate?
    public var logHandler: ((String, MicroTechBluetoothLogType) -> Void)? {
        get { bluetoothLogQueue.handler }
        set { bluetoothLogQueue.handler = newValue }
    }
    public static let defaultConnectionTimeout: TimeInterval = 15
    public static let defaultConfigurationTimeout: TimeInterval = MicroTechPeripheralManager.defaultOperationTimeout * 2 + 2
    public static let defaultScanTimeout: TimeInterval = 30
    static let restoreIdentifier = "com.loopkit.MicroTechCGM"

    public private(set) var activeRemoteIdentifier: UUID?
    private let log = OSLog(category: "MicroTechBluetoothManager")
    private let bluetoothLogQueue = MicroTechGattLogQueue(
        label: "com.loopkit.MicroTechCGM.bluetooth-log"
    )

    private let managerQueue = DispatchQueue(label: "com.loopkit.MicroTechCGM.bluetoothManager")
    private let managerQueueSpecificKey = DispatchSpecificKey<Bool>()
    private lazy var connectionTimeouts = MicroTechConnectionTimeoutController(
        timeout: Self.defaultConnectionTimeout,
        queue: managerQueue
    )
    private lazy var configurationTimeouts = MicroTechConnectionTimeoutController(
        timeout: Self.defaultConfigurationTimeout,
        queue: managerQueue
    )
    private var scanTimeoutWorkItem: DispatchWorkItem?
    private var centralManager: CBCentralManager!
    private var lastCentralState: CBManagerState?
    private let disconnectCallbackState = MicroTechDisconnectCallbackState()
    private var managedPeripherals: [UUID: MicroTechPeripheralManager] = [:]
    private var restoredPeripherals: [UUID: CBPeripheral] = [:]
    private var configuringPeripheralIDs: Set<UUID> = []
    private var connectionMode: MicroTechCGMConnectionMode
    private var broadcastScanPhase: MicroTechBroadcastScanPhase = .filtered
    private var activePeripheralManager: MicroTechPeripheralManager? {
        didSet {
            activeRemoteIdentifier = activePeripheralManager?.deviceIdentifier
        }
    }

    public init(initialConnectionMode: MicroTechCGMConnectionMode = .direct) {
        connectionMode = initialConnectionMode
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

    public func configureConnectionMode(_ mode: MicroTechCGMConnectionMode) {
        managerQueue.async {
            self.connectionMode = mode
        }
    }

    public func scan(remoteIdentifier: UUID? = nil) {
        managerQueue.async {
            self.connectionMode = .direct
            self.activeRemoteIdentifier = remoteIdentifier
            self.logBluetooth("scan requested, activeRemoteIdentifier \(String(describing: self.activeRemoteIdentifier))")
            self.scanIfReady()
        }
    }

    public func scanForBroadcast(remoteIdentifier: UUID? = nil) {
        managerQueue.async {
            self.connectionMode = .broadcast
            self.activeRemoteIdentifier = remoteIdentifier
            self.broadcastScanPhase = .filtered
            self.logBluetooth("broadcast scan requested, activeRemoteIdentifier \(String(describing: self.activeRemoteIdentifier))")
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
            self.stopScanningOnQueue(reason: "disconnect")
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

        if connectionMode == .broadcast {
            scanForBroadcastIfReady()
            return
        }

        if let identifier = activeRemoteIdentifier,
           let peripheral = restoredPeripherals[identifier]
        {
            logBluetooth(Self.savedPeripheralLogMessage(identifier: identifier, name: peripheral.name, source: .coreBluetoothRestore))
            logBluetooth(Self.restoredPeripheralLogMessage(identifier: identifier, source: .coreBluetoothRestore))
            if connectIfNeeded(peripheral, advertisedName: peripheral.name) {
                return
            }
        }

        if let identifier = activeRemoteIdentifier,
           let peripheral = centralManager.retrievePeripherals(withIdentifiers: [identifier]).first
        {
            logBluetooth(Self.savedPeripheralLogMessage(identifier: identifier, name: peripheral.name, source: .retrievePeripherals))
            logBluetooth(Self.restoredPeripheralLogMessage(identifier: identifier, source: .retrievePeripherals))
            if connectIfNeeded(peripheral, advertisedName: peripheral.name) {
                return
            }
        }

        for peripheral in centralManager.retrieveConnectedPeripherals(withServices: [MicroTechAidexProfile.serviceUUID]) {
            logBluetooth("found connected peripheral \(peripheral.identifier), name \(String(describing: peripheral.name))")
            if connectIfNeeded(peripheral, advertisedName: peripheral.name) {
                return
            }
        }

        guard activePeripheralManager == nil else {
            return
        }

        centralManager.registerForConnectionEvents(options: [
            CBConnectionEventMatchingOption.serviceUUIDs: [MicroTechAidexProfile.serviceUUID],
        ])
        logBluetooth(Self.scanStartedLogMessage(requestedIdentifier: activeRemoteIdentifier))
        centralManager.scanForPeripherals(withServices: [MicroTechAidexProfile.serviceUUID], options: nil)
        scheduleScanTimeout(remoteIdentifier: activeRemoteIdentifier)
    }

    private func scanForBroadcastIfReady() {
        guard activePeripheralManager == nil else {
            return
        }
        if centralManager.isScanning {
            return
        }

        startBroadcastScanOnQueue(phase: broadcastScanPhase)
    }

    private func startBroadcastScanOnQueue(phase: MicroTechBroadcastScanPhase) {
        guard activePeripheralManager == nil else {
            return
        }
        if centralManager.isScanning {
            return
        }

        broadcastScanPhase = phase
        logBluetooth(Self.broadcastScanStartedLogMessage(
            requestedIdentifier: activeRemoteIdentifier,
            phase: phase
        ))
        centralManager.scanForPeripherals(
            withServices: Self.broadcastScanServiceFilter(phase: phase),
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
        scheduleScanTimeout(remoteIdentifier: activeRemoteIdentifier)
    }

    private func stopScanningOnQueue(reason: String = "requested") {
        let wasScanning = centralManager.isScanning || scanTimeoutWorkItem != nil
        cancelScanTimeout()
        guard wasScanning else {
            return
        }

        let stoppedLogMessage = connectionMode == .broadcast
            ? Self.broadcastScanStoppedLogMessage(reason: reason)
            : Self.scanStoppedLogMessage(reason: reason)
        logBluetooth(stoppedLogMessage)
        if centralManager.isScanning {
            centralManager.stopScan()
        }
    }

    private func syncOnManagerQueue<Value>(_ work: () -> Value) -> Value {
        if DispatchQueue.getSpecific(key: managerQueueSpecificKey) == true {
            return work()
        }

        return managerQueue.sync(execute: work)
    }

    @discardableResult
    private func connectIfNeeded(_ peripheral: CBPeripheral, advertisedName: String?) -> Bool {
        let deviceName = advertisedName ?? peripheral.name ?? ""
        let shouldConnectByIdentifier = activeRemoteIdentifier == peripheral.identifier

        if !shouldConnectByIdentifier,
           delegate?.microTechBluetoothManager(self, shouldConnectToDeviceName: deviceName, identifier: peripheral.identifier) != true
        {
            logBluetooth(Self.scanDecisionLogMessage(
                accepted: false,
                identifier: peripheral.identifier,
                reason: "delegateRejected"
            ))
            return false
        }

        guard Self.shouldClaimPeripheralForConnection(state: peripheral.state) else {
            logBluetooth(Self.scanDecisionLogMessage(
                accepted: false,
                identifier: peripheral.identifier,
                reason: "peripheralDisconnecting"
            ))
            logBluetooth(Self.disconnectingPeripheralLogMessage(identifier: peripheral.identifier, name: deviceName))
            centralManager.cancelPeripheralConnection(peripheral)
            return false
        }

        logBluetooth(Self.scanDecisionLogMessage(
            accepted: true,
            identifier: peripheral.identifier,
            reason: shouldConnectByIdentifier ? "requestedIdentifier" : "delegateAccepted"
        ))
        let manager = managedPeripherals[peripheral.identifier] ?? MicroTechPeripheralManager(
            peripheral: peripheral,
            centralManager: centralManager,
            advertisedName: deviceName,
            logQueue: bluetoothLogQueue
        )
        manager.updateAdvertisedName(deviceName)
        manager.delegate = self
        manager.willCancelConnection = { [weak self] identifier in
            self?.disconnectCallbackState.expectCancellation(identifier: identifier)
        }
        managedPeripherals[peripheral.identifier] = manager
        activePeripheralManager = manager
        cancelScanTimeout()

        switch peripheral.state {
        case .connected:
            cancelConnectionTimeout(for: manager.deviceIdentifier)
            logBluetooth(Self.connectionLogMessage(event: "succeeded", identifier: peripheral.identifier))
            logBluetooth("configuring connected peripheral \(peripheral.identifier), name \(manager.deviceName)")
            configureAndNotifyReady(manager)
        case .disconnected:
            logBluetooth(Self.connectionLogMessage(event: "attempted", identifier: peripheral.identifier))
            logBluetooth("connecting peripheral \(peripheral.identifier), name \(manager.deviceName)")
            scheduleConnectionTimeout(for: manager)
            centralManager.connect(peripheral)
        case .connecting:
            logBluetooth(Self.connectionLogMessage(event: "attempted", identifier: peripheral.identifier))
            logBluetooth("peripheral already connecting \(peripheral.identifier), name \(manager.deviceName)")
            scheduleConnectionTimeoutIfNeeded(for: manager, state: peripheral.state)
        case .disconnecting:
            logBluetooth(Self.disconnectingPeripheralLogMessage(identifier: peripheral.identifier, name: manager.deviceName))
            centralManager.cancelPeripheralConnection(peripheral)
            return false
        @unknown default:
            logBluetooth("peripheral unknown state \(peripheral.identifier), name \(manager.deviceName)")
            scheduleConnectionTimeout(for: manager)
        }
        return true
    }

    private func configureAndNotifyReady(_ manager: MicroTechPeripheralManager) {
        let identifier = manager.deviceIdentifier
        cancelConnectionTimeout(for: identifier)
        guard configuringPeripheralIDs.insert(identifier).inserted else {
            logBluetooth(Self.configurationAlreadyInProgressLogMessage(identifier: identifier, name: manager.deviceName))
            return
        }
        scheduleConfigurationTimeout(for: manager)

        DispatchQueue.global(qos: .utility).async {
            do {
                try manager.configure()
                self.managerQueue.async {
                    self.configuringPeripheralIDs.remove(identifier)
                    self.cancelConfigurationTimeout(for: identifier)
                    guard self.managedPeripherals[identifier] === manager else {
                        return
                    }
                    self.stopScanningOnQueue(reason: "connected")
                    self.logBluetooth("peripheral ready \(identifier), name \(manager.deviceName)")
                    self.delegate?.microTechBluetoothManager(self, didReady: manager)
                }
            } catch {
                self.managerQueue.async {
                    self.configuringPeripheralIDs.remove(identifier)
                    self.cancelConfigurationTimeout(for: identifier)
                    guard self.managedPeripherals[identifier] === manager else {
                        return
                    }
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
        cancelConfigurationTimeout(for: identifier)
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
        bluetoothLogQueue.submit(MicroTechGattLogEntry(message: message, type: type))
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
        case .disconnected, .connecting:
            return true
        case .disconnecting:
            return false
        @unknown default:
            return true
        }
    }

    static func shouldClaimPeripheralForConnection(state: CBPeripheralState) -> Bool {
        switch state {
        case .connected, .disconnected, .connecting:
            return true
        case .disconnecting:
            return false
        @unknown default:
            return true
        }
    }

    static func savedPeripheralLogMessage(identifier: UUID, name: String?, source: SavedPeripheralSource) -> String {
        "retrieved saved peripheral \(identifier) from \(source.rawValue), name \(String(describing: name))"
    }

    static func scanStartedLogMessage(requestedIdentifier: UUID?) -> String {
        "stage=scan event=started requestedIdentifier=\(requestedIdentifier?.uuidString ?? "nil")"
    }

    static func scanFoundLogMessage(identifier: UUID, name: String?, advertisement: String, rssi: NSNumber) -> String {
        "stage=scan event=found identifier=\(identifier) name=\(name ?? "nil") advertisement=\(advertisement) rssi=\(rssi)"
    }

    static func broadcastScanStartedLogMessage(requestedIdentifier: UUID?) -> String {
        "stage=broadcast event=started requestedIdentifier=\(requestedIdentifier?.uuidString ?? "nil")"
    }

    static func broadcastScanStartedLogMessage(
        requestedIdentifier: UUID?,
        phase: MicroTechBroadcastScanPhase
    ) -> String {
        switch phase {
        case .filtered:
            return broadcastScanStartedLogMessage(requestedIdentifier: requestedIdentifier)
        case .unfiltered:
            return "stage=broadcast event=started phase=unfiltered requestedIdentifier=\(requestedIdentifier?.uuidString ?? "nil") services=nil"
        }
    }

    static func broadcastFoundLogMessage(identifier: UUID, name: String?, advertisement: String, rssi: NSNumber) -> String {
        "stage=broadcast event=found identifier=\(identifier) name=\(name ?? "nil") advertisement=\(advertisement) rssi=\(rssi)"
    }

    static func broadcastScanStoppedLogMessage(reason: String) -> String {
        "stage=broadcast event=stopped reason=\(reason)"
    }

    static func broadcastScanTimeoutLogMessage(requestedIdentifier: UUID?) -> String {
        "stage=broadcast event=timeout requestedIdentifier=\(requestedIdentifier?.uuidString ?? "nil")"
    }

    static func broadcastScanFallbackLogMessage(requestedIdentifier: UUID?) -> String {
        "stage=broadcast event=fallback reason=filteredTimeout requestedIdentifier=\(requestedIdentifier?.uuidString ?? "nil") nextServices=nil"
    }

    static func broadcastScanServiceFilter(phase: MicroTechBroadcastScanPhase) -> [CBUUID]? {
        switch phase {
        case .filtered:
            return [MicroTechAidexProfile.serviceUUID]
        case .unfiltered:
            return nil
        }
    }

    static func isMicroTechBroadcastAdvertisement(_ advertisementData: [String: Any]) -> Bool {
        guard let manufacturerData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data,
              manufacturerData.count >= 2
        else {
            return false
        }
        return manufacturerData[manufacturerData.startIndex] == 0x59 &&
            manufacturerData[manufacturerData.index(after: manufacturerData.startIndex)] == 0x00
    }

    static func discoveryLogMessages(
        connectionMode: MicroTechCGMConnectionMode,
        identifier: UUID,
        name: String?,
        advertisement: String,
        rssi: NSNumber
    ) -> [String] {
        switch connectionMode {
        case .direct:
            return [scanFoundLogMessage(
                identifier: identifier,
                name: name,
                advertisement: advertisement,
                rssi: rssi
            )]
        case .broadcast:
            return [broadcastFoundLogMessage(
                identifier: identifier,
                name: name,
                advertisement: advertisement,
                rssi: rssi
            )]
        }
    }

    static func advertisementDescription(_ advertisementData: [String: Any]) -> String {
        guard !advertisementData.isEmpty else {
            return "nil"
        }
        return advertisementData.keys.sorted().map { key in
            "\(key)=\(advertisementValueDescription(advertisementData[key]!))"
        }.joined(separator: ",")
    }

    private static func advertisementValueDescription(_ value: Any) -> String {
        if let data = value as? Data {
            return "Data(length=\(data.count),hex=\(data.microTechHexadecimalString))"
        }
        if let uuid = value as? CBUUID {
            return uuid.uuidString.uppercased()
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        if let string = value as? String {
            return string
        }
        if let dictionary = value as? NSDictionary {
            var entries: [(key: String, value: String)] = []
            for (key, value) in dictionary {
                entries.append((
                    key: advertisementValueDescription(key),
                    value: advertisementValueDescription(value)
                ))
            }
            entries.sort {
                $0.key == $1.key ? $0.value < $1.value : $0.key < $1.key
            }
            return "{\(entries.map { "\($0.key)=\($0.value)" }.joined(separator: ","))}"
        }
        if let array = value as? NSArray {
            return "[\(array.map(advertisementValueDescription).joined(separator: ","))]"
        }
        return String(describing: value)
    }

    static func scanDecisionLogMessage(accepted: Bool, identifier: UUID, reason: String) -> String {
        "stage=scan event=\(accepted ? "accepted" : "rejected") identifier=\(identifier) reason=\(reason)"
    }

    static func scanStoppedLogMessage(reason: String) -> String {
        "stage=scan event=stopped reason=\(reason)"
    }

    static func scanTimeoutLogMessage(requestedIdentifier: UUID?) -> String {
        "stage=scan event=timeout requestedIdentifier=\(requestedIdentifier?.uuidString ?? "nil")"
    }

    static func connectionLogMessage(event: String, identifier: UUID, error: Error? = nil) -> String {
        let base = "stage=connect event=\(event) identifier=\(identifier)"
        guard event == "failed" || error != nil else {
            return base
        }
        return "\(base) \(MicroTechDiagnosticLog.errorFields(error))"
    }

    static func restoredPeripheralLogMessage(identifier: UUID, source: SavedPeripheralSource) -> String {
        let sourceName: String
        switch source {
        case .coreBluetoothRestore:
            sourceName = "CoreBluetoothRestore"
        case .retrievePeripherals:
            sourceName = "retrievePeripherals"
        }
        return "stage=restore event=restored identifier=\(identifier) source=\(sourceName)"
    }

    static func bluetoothStateChangedLogMessage(
        oldState: CBManagerState?,
        newState: CBManagerState,
        stoppedOperation: String?
    ) -> String {
        "stage=bluetooth event=state_changed oldState=\(oldState.map(stateName) ?? "nil") newState=\(stateName(newState)) stoppedOperation=\(stoppedOperation ?? "nil")"
    }

    static func missingPeripheralManagerLogMessage(callback: String, identifier: UUID) -> String {
        "stage=callback event=ignored callback=\(callback) identifier=\(identifier) reason=missingPeripheralManager"
    }

    static func configurationAlreadyInProgressLogMessage(identifier: UUID, name: String) -> String {
        "peripheral configure already in progress \(identifier), name \(name)"
    }

    static func configurationTimedOutLogMessage(identifier: UUID, name: String) -> String {
        "peripheral configure timed out \(identifier), name \(name)"
    }

    static func disconnectingPeripheralLogMessage(identifier: UUID, name: String) -> String {
        "peripheral is disconnecting \(identifier), name \(name), waiting for disconnect before reconnecting"
    }

    private func cancelConnectionTimeout(for identifier: UUID) {
        connectionTimeouts.cancel(identifier: identifier)
    }

    private func scheduleConfigurationTimeout(for manager: MicroTechPeripheralManager) {
        let identifier = manager.deviceIdentifier
        configurationTimeouts.schedule(identifier: identifier) { [weak self] identifier in
            self?.handleConfigurationTimeout(identifier: identifier)
        }
    }

    private func cancelConfigurationTimeout(for identifier: UUID) {
        configurationTimeouts.cancel(identifier: identifier)
    }

    private func handleConfigurationTimeout(identifier: UUID) {
        guard configuringPeripheralIDs.contains(identifier),
              let manager = managedPeripherals[identifier],
              activePeripheralManager === manager
        else {
            return
        }

        let error = MicroTechBluetoothManagerError.configureTimeout(identifier)
        logBluetooth(Self.configurationTimedOutLogMessage(identifier: identifier, name: manager.deviceName), type: .error)
        removeManager(manager, cancelConnection: true)
        delegate?.microTechBluetoothManager(self, didFailWith: error)
        scanIfReady()
    }

    private func handleConnectionTimeout(identifier: UUID) {
        guard let manager = managedPeripherals[identifier],
              activePeripheralManager === manager,
              !manager.isConnected else
        {
            return
        }

        let error = MicroTechBluetoothManagerError.connectTimeout(identifier)
        logBluetooth(Self.connectionLogMessage(event: "timeout", identifier: identifier), type: .error)
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
        let timeoutLogMessage = connectionMode == .broadcast
            ? Self.broadcastScanTimeoutLogMessage(requestedIdentifier: remoteIdentifier)
            : Self.scanTimeoutLogMessage(requestedIdentifier: remoteIdentifier)
        logBluetooth(timeoutLogMessage, type: .error)
        logBluetooth("scan timed out, remoteIdentifier \(String(describing: remoteIdentifier))", type: .error)
        if connectionMode == .broadcast, broadcastScanPhase == .filtered {
            logBluetooth(Self.broadcastScanFallbackLogMessage(requestedIdentifier: remoteIdentifier))
            stopScanningOnQueue(reason: "filteredTimeoutFallback")
            startBroadcastScanOnQueue(phase: .unfiltered)
            return
        }

        stopScanningOnQueue(reason: "timeout")
        delegate?.microTechBluetoothManager(self, didFailWith: error)
    }
}

extension MicroTechBluetoothManager: MicroTechBluetoothManaging {
}

extension MicroTechBluetoothManager: CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let stoppedOperation: String?
        if central.state != .poweredOn {
            if central.isScanning || scanTimeoutWorkItem != nil {
                stoppedOperation = "scan"
            } else if !configuringPeripheralIDs.isEmpty {
                stoppedOperation = "configure"
            } else if let manager = activePeripheralManager, !manager.isConnected {
                stoppedOperation = "connect"
            } else {
                stoppedOperation = nil
            }
        } else {
            stoppedOperation = nil
        }
        logBluetooth(Self.bluetoothStateChangedLogMessage(
            oldState: lastCentralState,
            newState: central.state,
            stoppedOperation: stoppedOperation
        ))
        lastCentralState = central.state

        guard central.state == .poweredOn else {
            logBluetooth("central state changed to \(central.state.rawValue), stopping scan")
            stopScanningOnQueue(reason: "bluetoothStateLoss")
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
            logBluetooth(Self.restoredPeripheralLogMessage(
                identifier: peripheral.identifier,
                source: .coreBluetoothRestore
            ))
            restoredPeripherals[peripheral.identifier] = peripheral
            guard connectionMode == .direct else {
                continue
            }
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
        if connectionMode == .broadcast,
           !Self.isMicroTechBroadcastAdvertisement(advertisementData)
        {
            return
        }
        for message in Self.discoveryLogMessages(
            connectionMode: connectionMode,
            identifier: peripheral.identifier,
            name: advertisedName ?? peripheral.name,
            advertisement: Self.advertisementDescription(advertisementData),
            rssi: RSSI
        ) {
            logBluetooth(message)
        }
        logBluetooth("didDiscover peripheral \(peripheral.identifier), advertisedName \(String(describing: advertisedName)), peripheralName \(String(describing: peripheral.name)), rssi \(RSSI)")
        guard connectionMode == .direct else {
            delegate?.microTechBluetoothManager(
                self,
                didDiscoverBroadcast: MicroTechBroadcastAdvertisement(
                    identifier: peripheral.identifier,
                    localName: advertisedName,
                    peripheralName: peripheral.name,
                    advertisementData: advertisementData,
                    rssi: RSSI,
                    discoveredAt: Date()
                )
            )
            return
        }
        connectIfNeeded(peripheral, advertisedName: advertisedName)
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard let manager = managedPeripherals[peripheral.identifier] else {
            logBluetooth(Self.missingPeripheralManagerLogMessage(
                callback: "didConnect",
                identifier: peripheral.identifier
            ), type: .error)
            return
        }

        cancelConnectionTimeout(for: peripheral.identifier)
        logBluetooth(Self.connectionLogMessage(event: "succeeded", identifier: peripheral.identifier))
        logBluetooth("didConnect peripheral \(peripheral.identifier), name \(manager.deviceName)")
        configureAndNotifyReady(manager)
    }

    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        let manager = managedPeripherals[peripheral.identifier]
        let result = disconnectCallbackState.handleConnectionEnd(
            callback: "didFailToConnect",
            identifier: peripheral.identifier,
            error: error,
            managerPresent: manager != nil,
            log: { self.logBluetooth($0, type: $1) }
        )
        if result == .expectedCancellation {
            if let manager {
                removeManager(manager, cancelConnection: false)
            }
            scanIfReady()
            return
        }
        if result == .managedPeripheral, let manager {
            removeManager(manager, cancelConnection: false)
        }
        logBluetooth(
            Self.connectionLogMessage(event: "failed", identifier: peripheral.identifier, error: error),
            type: .error
        )
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
        let manager = managedPeripherals[peripheral.identifier]
        let result = disconnectCallbackState.handleConnectionEnd(
            callback: "didDisconnectPeripheral",
            identifier: peripheral.identifier,
            error: error,
            managerPresent: manager != nil,
            log: { self.logBluetooth($0, type: $1) }
        )
        if result == .expectedCancellation {
            if let manager {
                removeManager(manager, cancelConnection: false)
            }
            scanIfReady()
            return
        }
        guard result == .managedPeripheral, let manager else {
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
        guard connectionMode == .direct else {
            logBluetooth("connection event ignored in broadcast mode peripheral \(peripheral.identifier)")
            return
        }
        switch event {
        case .peerConnected:
            connectIfNeeded(peripheral, advertisedName: peripheral.name)
        case .peerDisconnected:
            logBluetooth(Self.connectionLogMessage(
                event: "disconnected",
                identifier: peripheral.identifier
            ))
            if let manager = managedPeripherals[peripheral.identifier] {
                manager.didDisconnect(error: nil)
                removeManager(manager, cancelConnection: false)
            } else {
                logBluetooth(Self.missingPeripheralManagerLogMessage(
                    callback: "connectionEventPeerDisconnected",
                    identifier: peripheral.identifier
                ), type: .error)
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
    static func stateName(_ state: CBManagerState) -> String {
        switch state {
        case .unknown:
            return "unknown"
        case .resetting:
            return "resetting"
        case .unsupported:
            return "unsupported"
        case .unauthorized:
            return "unauthorized"
        case .poweredOff:
            return "poweredOff"
        case .poweredOn:
            return "poweredOn"
        @unknown default:
            return "unknown(\(state.rawValue))"
        }
    }

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
