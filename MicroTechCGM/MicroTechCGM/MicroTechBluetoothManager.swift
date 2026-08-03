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

protocol MicroTechConnectionTimeoutControlling: AnyObject {
    func schedule(identifier: UUID, handler: @escaping (UUID) -> Void)
    func cancel(identifier: UUID)
    func cancelAll()
}

final class MicroTechConnectionTimeoutController: MicroTechConnectionTimeoutControlling {
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

    func cancelAll() {
        let scheduledWorkItems = Array(workItems.values)
        workItems.removeAll()
        scheduledWorkItems.forEach { $0.cancel() }
    }
}

protocol MicroTechManagedPeripheral: MicroTechPeripheralSession {
    var delegate: MicroTechPeripheralManagerDelegate? { get set }
    var willCancelConnection: ((UUID) -> Void)? { get set }
    var isConnected: Bool { get }

    func updateAdvertisedName(_ advertisedName: String?)
    func configure() throws
    func didDisconnect(error: Error?)
}

extension MicroTechPeripheralManager: MicroTechManagedPeripheral {
}

protocol MicroTechRestoredPeripheralReference: AnyObject {
    var identifier: UUID { get }
    var name: String? { get }
    var peripheral: CBPeripheral? { get }
}

private final class MicroTechCoreBluetoothPeripheralReference: MicroTechRestoredPeripheralReference {
    let identifier: UUID
    let name: String?
    let peripheral: CBPeripheral?

    init(peripheral: CBPeripheral) {
        identifier = peripheral.identifier
        name = peripheral.name
        self.peripheral = peripheral
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
    func shutdown(completion: @escaping () -> Void)
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

struct MicroTechBluetoothManagerStateSnapshot: Equatable {
    let isShutdown: Bool
    let activeRemoteIdentifier: UUID?
    let managedPeripheralCount: Int
    let restoredPeripheralCount: Int
    let configuringPeripheralCount: Int
    let hasScanTimeout: Bool
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

    private let managerQueue: DispatchQueue
    private let managerQueueSpecificKey = DispatchSpecificKey<Bool>()
    private let connectionTimeouts: MicroTechConnectionTimeoutControlling
    private let configurationTimeouts: MicroTechConnectionTimeoutControlling
    private var scanTimeoutWorkItem: DispatchWorkItem?
    private var centralManager: CBCentralManager!
    private var lastCentralState: CBManagerState?
    private var centralStateObserversForTesting: [() -> Void] = []
    private let disconnectCallbackState = MicroTechDisconnectCallbackState()
    private var managedPeripherals: [UUID: MicroTechManagedPeripheral] = [:]
    private var restoredPeripherals: [UUID: MicroTechRestoredPeripheralReference] = [:]
    private var configuringPeripheralIDs: Set<UUID> = []
    private var isShutdown = false
    private var shutdownCleanupCompleted = false
    private var shutdownCompletions: [() -> Void] = []
    private var connectionMode: MicroTechCGMConnectionMode
    private var broadcastScanPhase: MicroTechBroadcastScanPhase = .filtered
    private var activePeripheralManager: MicroTechManagedPeripheral? {
        didSet {
            activeRemoteIdentifier = activePeripheralManager?.deviceIdentifier
        }
    }

    public convenience init(initialConnectionMode: MicroTechCGMConnectionMode = .direct) {
        self.init(
            initialConnectionMode: initialConnectionMode,
            centralManagerOptions: [CBCentralManagerOptionRestoreIdentifierKey: Self.restoreIdentifier]
        )
    }

    init(
        initialConnectionMode: MicroTechCGMConnectionMode,
        centralManagerOptions: [String: Any]?,
        connectionTimeouts: MicroTechConnectionTimeoutControlling? = nil,
        configurationTimeouts: MicroTechConnectionTimeoutControlling? = nil
    ) {
        let managerQueue = DispatchQueue(label: "com.loopkit.MicroTechCGM.bluetoothManager")
        self.managerQueue = managerQueue
        self.connectionTimeouts = connectionTimeouts ?? MicroTechConnectionTimeoutController(
            timeout: Self.defaultConnectionTimeout,
            queue: managerQueue
        )
        self.configurationTimeouts = configurationTimeouts ?? MicroTechConnectionTimeoutController(
            timeout: Self.defaultConfigurationTimeout,
            queue: managerQueue
        )
        connectionMode = initialConnectionMode
        super.init()

        managerQueue.setSpecific(key: managerQueueSpecificKey, value: true)
        managerQueue.sync {
            centralManager = CBCentralManager(
                delegate: self,
                queue: managerQueue,
                options: centralManagerOptions
            )
        }
    }

    func stateSnapshotForTesting() -> MicroTechBluetoothManagerStateSnapshot {
        syncOnManagerQueue {
            MicroTechBluetoothManagerStateSnapshot(
                isShutdown: isShutdown,
                activeRemoteIdentifier: activeRemoteIdentifier,
                managedPeripheralCount: managedPeripherals.count,
                restoredPeripheralCount: restoredPeripherals.count,
                configuringPeripheralCount: configuringPeripheralIDs.count,
                hasScanTimeout: scanTimeoutWorkItem != nil
            )
        }
    }

    func flushLogsForTesting() {
        bluetoothLogQueue.flush()
    }

    func whenCentralStateObservedForTesting(_ observer: @escaping () -> Void) {
        managerQueue.async {
            if self.lastCentralState != nil {
                observer()
            } else {
                self.centralStateObserversForTesting.append(observer)
            }
        }
    }

    func injectStateForTesting(
        activePeripheralManager: MicroTechManagedPeripheral?,
        managedPeripherals: [MicroTechManagedPeripheral],
        restoredPeripherals: [MicroTechRestoredPeripheralReference],
        configuringPeripheralIDs: Set<UUID>,
        hasScanTimeout: Bool
    ) {
        syncOnManagerQueue {
            self.managedPeripherals = Dictionary(
                uniqueKeysWithValues: managedPeripherals.map { ($0.deviceIdentifier, $0) }
            )
            self.restoredPeripherals = Dictionary(
                uniqueKeysWithValues: restoredPeripherals.map { ($0.identifier, $0) }
            )
            self.configuringPeripheralIDs = configuringPeripheralIDs
            self.scanTimeoutWorkItem = hasScanTimeout ? DispatchWorkItem {} : nil
            self.activePeripheralManager = activePeripheralManager
        }
    }

    public var isScanning: Bool {
        syncOnManagerQueue {
            !isShutdown && centralManager.isScanning
        }
    }

    public var isConnected: Bool {
        syncOnManagerQueue {
            !isShutdown && activePeripheralManager?.isConnected == true
        }
    }

    public func configureConnectionMode(_ mode: MicroTechCGMConnectionMode) {
        managerQueue.async {
            guard !self.isShutdown else {
                return
            }
            self.connectionMode = mode
        }
    }

    public func scan(remoteIdentifier: UUID? = nil) {
        managerQueue.async {
            guard !self.isShutdown else {
                return
            }
            self.connectionMode = .direct
            self.activeRemoteIdentifier = remoteIdentifier
            self.logBluetooth("scan requested, activeRemoteIdentifier \(String(describing: self.activeRemoteIdentifier))")
            self.scanIfReady()
        }
    }

    public func scanForBroadcast(remoteIdentifier: UUID? = nil) {
        managerQueue.async {
            guard !self.isShutdown else {
                return
            }
            self.connectionMode = .broadcast
            self.activeRemoteIdentifier = remoteIdentifier
            self.broadcastScanPhase = .filtered
            self.logBluetooth("broadcast scan requested, activeRemoteIdentifier \(String(describing: self.activeRemoteIdentifier))")
            self.scanIfReady()
        }
    }

    public func refreshConnectedPeripheral() {
        managerQueue.async {
            guard !self.isShutdown else {
                return
            }
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
            guard !self.isShutdown else {
                return
            }
            self.stopScanningOnQueue()
        }
    }

    public func disconnect() {
        managerQueue.async {
            guard !self.isShutdown else {
                return
            }
            self.stopScanningOnQueue(reason: "disconnect")
            if let manager = self.activePeripheralManager {
                self.removeManager(manager, cancelConnection: true)
            }
        }
    }

    public func forgetPeripheral() {
        managerQueue.async {
            guard !self.isShutdown else {
                return
            }
            self.activePeripheralManager = nil
            self.restoredPeripherals.removeAll()
        }
    }

    public func shutdown(completion: @escaping () -> Void) {
        managerQueue.async {
            if self.shutdownCleanupCompleted {
                completion()
                return
            }
            self.shutdownCompletions.append(completion)
            guard !self.isShutdown else {
                return
            }

            self.isShutdown = true
            self.stopScanningOnQueue(reason: "shutdown")
            self.cancelScanTimeout()
            self.connectionTimeouts.cancelAll()
            self.configurationTimeouts.cancelAll()

            let managers = Array(self.managedPeripherals.values)
            managers.forEach { self.removeManager($0, cancelConnection: true) }
            self.activePeripheralManager = nil
            self.managedPeripherals.removeAll()
            self.restoredPeripherals.removeAll()
            self.configuringPeripheralIDs.removeAll()
            self.delegate = nil
            self.bluetoothLogQueue.clearHandler {
                self.managerQueue.async {
                    self.shutdownCleanupCompleted = true
                    let completions = self.shutdownCompletions
                    self.shutdownCompletions.removeAll()
                    completions.forEach { $0() }
                }
            }
        }
    }

    private func scanIfReady() {
        guard !isShutdown else {
            return
        }
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
           let reference = restoredPeripherals[identifier],
           let peripheral = reference.peripheral
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
        guard !isShutdown else {
            return
        }
        guard activePeripheralManager == nil else {
            return
        }
        if centralManager.isScanning {
            return
        }

        startBroadcastScanOnQueue(phase: broadcastScanPhase)
    }

    private func startBroadcastScanOnQueue(phase: MicroTechBroadcastScanPhase) {
        guard !isShutdown else {
            return
        }
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
        guard !isShutdown else {
            return false
        }
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

    private func configureAndNotifyReady(_ manager: MicroTechManagedPeripheral) {
        guard !isShutdown else {
            return
        }
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
                    guard !self.isShutdown else {
                        return
                    }
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
                    guard !self.isShutdown else {
                        return
                    }
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

    private func removeManager(_ manager: MicroTechManagedPeripheral, cancelConnection: Bool) {
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

    private func scheduleConnectionTimeout(for manager: MicroTechManagedPeripheral) {
        guard !isShutdown else {
            return
        }
        let identifier = manager.deviceIdentifier
        connectionTimeouts.schedule(identifier: identifier) { [weak self] identifier in
            self?.handleConnectionTimeout(identifier: identifier)
        }
    }

    private func scheduleConnectionTimeoutIfNeeded(for manager: MicroTechManagedPeripheral, state: CBPeripheralState) {
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

    private func scheduleConfigurationTimeout(for manager: MicroTechManagedPeripheral) {
        guard !isShutdown else {
            return
        }
        let identifier = manager.deviceIdentifier
        configurationTimeouts.schedule(identifier: identifier) { [weak self] identifier in
            self?.handleConfigurationTimeout(identifier: identifier)
        }
    }

    private func cancelConfigurationTimeout(for identifier: UUID) {
        configurationTimeouts.cancel(identifier: identifier)
    }

    private func handleConfigurationTimeout(identifier: UUID) {
        guard !isShutdown,
              configuringPeripheralIDs.contains(identifier),
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
        guard !isShutdown,
              let manager = managedPeripherals[identifier],
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
        guard !isShutdown, Self.defaultScanTimeout > 0 else {
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
        guard !isShutdown,
              centralManager.isScanning,
              activePeripheralManager == nil else {
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
        guard !isShutdown else {
            return
        }
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
        let centralStateObservers = centralStateObserversForTesting
        centralStateObserversForTesting.removeAll()
        centralStateObservers.forEach { $0() }

        guard central.state == .poweredOn else {
            logBluetooth("central state changed to \(central.state.rawValue), stopping scan")
            stopScanningOnQueue(reason: "bluetoothStateLoss")
            return
        }
        logBluetooth("central powered on")
        scanIfReady()
    }

    public func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        guard !isShutdown else {
            return
        }
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
            restoredPeripherals[peripheral.identifier] = MicroTechCoreBluetoothPeripheralReference(
                peripheral: peripheral
            )
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
        handleDiscoveredPeripheral(
            identifier: peripheral.identifier,
            peripheralName: peripheral.name,
            advertisementData: advertisementData,
            rssi: RSSI
        ) {
            _ = self.connectIfNeeded(peripheral, advertisedName: advertisedName)
        }
    }

    func handleDiscoveredPeripheral(
        identifier: UUID,
        peripheralName: String?,
        advertisementData: [String: Any],
        rssi: NSNumber,
        connectIfNeeded: () -> Void
    ) {
        guard !isShutdown else {
            return
        }
        let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        if connectionMode == .broadcast,
           !Self.isMicroTechBroadcastAdvertisement(advertisementData)
        {
            return
        }
        for message in Self.discoveryLogMessages(
            connectionMode: connectionMode,
            identifier: identifier,
            name: advertisedName ?? peripheralName,
            advertisement: Self.advertisementDescription(advertisementData),
            rssi: rssi
        ) {
            logBluetooth(message)
        }
        logBluetooth("didDiscover peripheral \(identifier), advertisedName \(String(describing: advertisedName)), peripheralName \(String(describing: peripheralName)), rssi \(rssi)")
        guard connectionMode == .direct else {
            delegate?.microTechBluetoothManager(
                self,
                didDiscoverBroadcast: MicroTechBroadcastAdvertisement(
                    identifier: identifier,
                    localName: advertisedName,
                    peripheralName: peripheralName,
                    advertisementData: advertisementData,
                    rssi: rssi,
                    discoveredAt: Date()
                )
            )
            return
        }
        connectIfNeeded()
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        handleDidConnect(identifier: peripheral.identifier)
    }

    func handleDidConnect(identifier: UUID) {
        guard !isShutdown else {
            return
        }
        guard let manager = managedPeripherals[identifier] else {
            logBluetooth(Self.missingPeripheralManagerLogMessage(
                callback: "didConnect",
                identifier: identifier
            ), type: .error)
            return
        }

        cancelConnectionTimeout(for: identifier)
        logBluetooth(Self.connectionLogMessage(event: "succeeded", identifier: identifier))
        logBluetooth("didConnect peripheral \(identifier), name \(manager.deviceName)")
        configureAndNotifyReady(manager)
    }

    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        handleDidFailToConnect(identifier: peripheral.identifier, error: error)
    }

    func handleDidFailToConnect(identifier: UUID, error: Error?) {
        guard !isShutdown else {
            return
        }
        let manager = managedPeripherals[identifier]
        let result = disconnectCallbackState.handleConnectionEnd(
            callback: "didFailToConnect",
            identifier: identifier,
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
            Self.connectionLogMessage(event: "failed", identifier: identifier, error: error),
            type: .error
        )
        if let error {
            logBluetooth("didFailToConnect peripheral \(identifier), error \(String(describing: error))", type: .error)
        } else {
            logBluetooth("didFailToConnect peripheral \(identifier) without error", type: .error)
        }
        delegate?.microTechBluetoothManager(
            self,
            didFailWith: MicroTechBluetoothManagerError.connectFailed(identifier, error.map { String(describing: $0) })
        )
        scanIfReady()
    }

    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        handleDidDisconnect(identifier: peripheral.identifier, error: error)
    }

    func handleDidDisconnect(identifier: UUID, error: Error?) {
        guard !isShutdown else {
            return
        }
        let manager = managedPeripherals[identifier]
        let result = disconnectCallbackState.handleConnectionEnd(
            callback: "didDisconnectPeripheral",
            identifier: identifier,
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
            logBluetooth("didDisconnect peripheral \(identifier), error \(String(describing: error))", type: .error)
        } else {
            logBluetooth("didDisconnect peripheral \(identifier)")
        }
        manager.didDisconnect(error: error)
        removeManager(manager, cancelConnection: false)
        scanIfReady()
    }

    public func centralManager(_ central: CBCentralManager, connectionEventDidOccur event: CBConnectionEvent, for peripheral: CBPeripheral) {
        handleConnectionEvent(
            event,
            identifier: peripheral.identifier,
            peripheralName: peripheral.name
        ) {
            _ = self.connectIfNeeded(peripheral, advertisedName: peripheral.name)
        }
    }

    func handleConnectionEvent(
        _ event: CBConnectionEvent,
        identifier: UUID,
        peripheralName: String?,
        connectIfNeeded: () -> Void
    ) {
        guard !isShutdown else {
            return
        }
        logBluetooth("connection event \(Self.name(for: event)) peripheral \(identifier), name \(String(describing: peripheralName))")
        guard connectionMode == .direct else {
            logBluetooth("connection event ignored in broadcast mode peripheral \(identifier)")
            return
        }
        switch event {
        case .peerConnected:
            connectIfNeeded()
        case .peerDisconnected:
            logBluetooth(Self.connectionLogMessage(
                event: "disconnected",
                identifier: identifier
            ))
            if let manager = managedPeripherals[identifier] {
                manager.didDisconnect(error: nil)
                removeManager(manager, cancelConnection: false)
            } else {
                logBluetooth(Self.missingPeripheralManagerLogMessage(
                    callback: "connectionEventPeerDisconnected",
                    identifier: identifier
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
        handlePeripheralValue(value, characteristic: characteristic, session: manager)
    }

    func handlePeripheralValue(
        _ value: Data,
        characteristic: CBUUID,
        session: MicroTechPeripheralSession
    ) {
        guard !isShutdown else {
            return
        }
        delegate?.microTechBluetoothManager(self, didReceive: value, for: characteristic, session: session)
    }

    public func microTechPeripheralManager(_ manager: MicroTechPeripheralManager, didDisconnectWith error: Error?) {
        handlePeripheralDisconnect(manager, error: error)
    }

    func handlePeripheralDisconnect(_ manager: MicroTechManagedPeripheral, error: Error?) {
        guard !isShutdown else {
            return
        }
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
