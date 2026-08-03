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

enum MicroTechGattCallback: String {
    case discoverServices
    case discoverCharacteristics
    case notificationState
    case read
    case notificationValue
    case write
}

enum MicroTechGattOperation: Equatable {
    case discoverServices(CBUUID)
    case discoverCharacteristics(CBUUID)
    case notification(CBUUID)
    case read(CBUUID)
    case write(CBUUID)

    var name: String {
        switch self {
        case .discoverServices:
            return "discoverServices"
        case .discoverCharacteristics:
            return "discoverCharacteristics"
        case .notification:
            return "notificationState"
        case .read:
            return "read"
        case .write:
            return "write"
        }
    }

    var service: CBUUID? {
        switch self {
        case .discoverServices(let service), .discoverCharacteristics(let service):
            return service
        case .notification, .read, .write:
            return nil
        }
    }

    var characteristic: CBUUID? {
        switch self {
        case .notification(let characteristic), .read(let characteristic), .write(let characteristic):
            return characteristic
        case .discoverServices, .discoverCharacteristics:
            return nil
        }
    }
}

struct MicroTechGattLogEntry {
    let message: String
    let type: MicroTechBluetoothLogType
}

struct MicroTechGattLogBatch {
    let streamIdentifier: UUID
    let sequence: Int
    let entries: [MicroTechGattLogEntry]
    let completesStream: Bool

    init(
        streamIdentifier: UUID,
        sequence: Int,
        entries: [MicroTechGattLogEntry],
        completesStream: Bool = false
    ) {
        self.streamIdentifier = streamIdentifier
        self.sequence = sequence
        self.entries = entries
        self.completesStream = completesStream
    }
}

final class MicroTechGattLogQueue {
    typealias Handler = (String, MicroTechBluetoothLogType) -> Void

    private let queue: DispatchQueue
    private let queueSpecificKey = DispatchSpecificKey<UUID>()
    private let queueIdentity = UUID()
    private let preHandlerBufferCapacity: Int
    private var storedHandler: Handler?
    private var preHandlerEntries: [MicroTechGattLogEntry] = []
    private var orderedStreams: [
        UUID: (
            nextSequence: Int,
            pending: [Int: (entries: [MicroTechGattLogEntry], completesStream: Bool)]
        )
    ] = [:]

    init(label: String, preHandlerBufferCapacity: Int = 256) {
        queue = DispatchQueue(label: label)
        self.preHandlerBufferCapacity = max(0, preHandlerBufferCapacity)
        queue.setSpecific(key: queueSpecificKey, value: queueIdentity)
    }

    var handler: Handler? {
        get {
            syncOnQueue { storedHandler }
        }
        set {
            syncOnQueue {
                storedHandler = newValue
                guard newValue != nil, !preHandlerEntries.isEmpty else {
                    return
                }
                let entries = preHandlerEntries
                preHandlerEntries.removeAll(keepingCapacity: true)
                deliver(entries)
            }
        }
    }

    var orderedStreamCount: Int {
        syncOnQueue { orderedStreams.count }
    }

    func submit(_ entry: MicroTechGattLogEntry) {
        queue.async {
            self.deliver([entry])
        }
    }

    func submit(_ batch: MicroTechGattLogBatch) {
        queue.async {
            var stream = self.orderedStreams[batch.streamIdentifier] ?? (
                nextSequence: 0,
                pending: [:]
            )
            guard batch.sequence >= stream.nextSequence else {
                return
            }
            stream.pending[batch.sequence] = (batch.entries, batch.completesStream)
            while let pendingBatch = stream.pending.removeValue(forKey: stream.nextSequence) {
                self.deliver(pendingBatch.entries)
                stream.nextSequence += 1
                if pendingBatch.completesStream {
                    self.orderedStreams.removeValue(forKey: batch.streamIdentifier)
                    return
                }
            }
            self.orderedStreams[batch.streamIdentifier] = stream
        }
    }

    func flush() {
        syncOnQueue {}
    }

    func clearHandler(completion: @escaping () -> Void) {
        queue.async {
            self.storedHandler = nil
            completion()
        }
    }

    private func deliver(_ entries: [MicroTechGattLogEntry]) {
        guard let handler = storedHandler else {
            guard preHandlerBufferCapacity > 0 else {
                return
            }
            preHandlerEntries.append(contentsOf: entries)
            let overflow = preHandlerEntries.count - preHandlerBufferCapacity
            if overflow > 0 {
                preHandlerEntries.removeFirst(overflow)
            }
            return
        }
        entries.forEach { handler($0.message, $0.type) }
    }

    private func syncOnQueue<Value>(_ work: () -> Value) -> Value {
        if DispatchQueue.getSpecific(key: queueSpecificKey) == queueIdentity {
            return work()
        }
        return queue.sync(execute: work)
    }
}

enum MicroTechGattWaitResult: Equatable {
    case completed
    case timedOut
}

final class MicroTechGattOperationState {
    private let condition = NSCondition()
    private let logStreamIdentifier = UUID()
    private var nextLogSequence = 0
    private var pendingOperation: MicroTechGattOperation?
    private var pendingError: Error?
    private var pendingCompleted = false
    private var pendingCallbackArrived = false
    private var notificationValueAttemptSubmitted: Set<CBUUID> = []
    private var sessionInvalidated = false
    private var invalidatedOperation: MicroTechGattOperation?
    private var disconnectRequested = false
    private var logStreamCompleted = false

    func begin(_ operation: MicroTechGattOperation) throws {
        condition.lock()
        defer { condition.unlock() }
        guard !sessionInvalidated else {
            throw MicroTechPeripheralManagerError.notConnected
        }
        guard pendingOperation == nil else {
            throw MicroTechPeripheralManagerError.invalidCommand
        }
        pendingOperation = operation
        pendingError = nil
        pendingCompleted = false
        pendingCallbackArrived = false
        if case .notification(let characteristic) = operation {
            notificationValueAttemptSubmitted.remove(characteristic)
        }
    }

    func validateImmediateCommand() throws {
        condition.lock()
        defer { condition.unlock() }
        guard !sessionInvalidated else {
            throw MicroTechPeripheralManagerError.notConnected
        }
        guard pendingOperation == nil else {
            throw MicroTechPeripheralManagerError.invalidCommand
        }
    }

    func wait(
        timeout: TimeInterval,
        onTimeout: (() -> Void)? = nil
    ) throws -> MicroTechGattWaitResult {
        condition.lock()
        let deadline = Date(timeIntervalSinceNow: timeout)
        while !pendingCompleted {
            if !condition.wait(until: deadline), !pendingCompleted {
                sessionInvalidated = true
                invalidatedOperation = pendingOperation
                clearPendingLocked()
                condition.unlock()
                onTimeout?()
                return .timedOut
            }
        }
        let error = pendingError
        clearPendingLocked()
        condition.unlock()
        if let error {
            throw error
        }
        return .completed
    }

    var isSessionInvalidated: Bool {
        condition.lock()
        defer { condition.unlock() }
        return sessionInvalidated
    }

    func invalidateSession(_ error: Error = MicroTechPeripheralManagerError.notConnected) {
        condition.lock()
        sessionInvalidated = true
        invalidatedOperation = pendingOperation ?? invalidatedOperation
        if pendingOperation != nil {
            pendingError = error
            pendingCompleted = true
            condition.signal()
        }
        condition.unlock()
    }

    func completeLogStream(log: (MicroTechGattLogBatch) -> Void) {
        condition.lock()
        guard !logStreamCompleted else {
            condition.unlock()
            return
        }
        logStreamCompleted = true
        let batch = makeLogBatchLocked([], completesStream: true)
        condition.unlock()
        log(batch)
    }

    func requestDisconnect() -> Bool {
        condition.lock()
        if let pendingOperation, !pendingCompleted {
            invalidatedOperation = pendingOperation
            pendingError = MicroTechPeripheralManagerError.notConnected
            pendingCompleted = true
            condition.signal()
        }
        sessionInvalidated = true
        guard !disconnectRequested else {
            condition.unlock()
            return false
        }
        disconnectRequested = true
        condition.unlock()
        return true
    }

    private func clearPendingLocked() {
        pendingOperation = nil
        pendingError = nil
        pendingCompleted = false
        pendingCallbackArrived = false
    }

    func failPending(_ error: Error) {
        condition.lock()
        if pendingOperation != nil {
            pendingError = error
            pendingCompleted = true
            condition.signal()
        }
        condition.unlock()
    }

    func handleOperationCallback(
        callback: MicroTechGattCallback,
        identifier: UUID,
        service: CBUUID?,
        characteristic: CBUUID?,
        error: Error?,
        discoveredServiceUUIDs: [CBUUID]? = nil,
        discoveredCharacteristicUUIDs: [CBUUID]? = nil,
        log: (MicroTechGattLogBatch) -> Void
    ) {
        condition.lock()
        guard !logStreamCompleted else {
            condition.unlock()
            return
        }
        if sessionInvalidated {
            let pendingName = pendingOperation?.name ?? invalidatedOperation?.name
            let batch = makeLogBatchLocked([
                MicroTechPeripheralManager.ignoredCallbackLogEntry(
                    callback: callback,
                    identifier: identifier,
                    service: service,
                    characteristic: characteristic,
                    reason: "sessionInvalidated",
                    pendingOperation: pendingName
                ),
            ])
            condition.unlock()
            log(batch)
            return
        }
        let expectedOperation = operation(
            for: callback,
            service: service,
            characteristic: characteristic
        )
        guard
            let expectedOperation,
            pendingOperation == expectedOperation,
            !pendingCompleted,
            !pendingCallbackArrived
        else {
            let pendingName = pendingOperation?.name
            let operationAlreadyCompleted = pendingOperation == expectedOperation && pendingCompleted
            let callbackAlreadyArrived = pendingOperation == expectedOperation && pendingCallbackArrived
            let reason: String
            if operationAlreadyCompleted {
                reason = "operationAlreadyCompleted"
            } else if callbackAlreadyArrived {
                reason = "callbackAlreadyArrived"
            } else {
                reason = pendingName == nil ? "missingPendingOperation" : "pendingOperationMismatch"
            }
            let batch = makeLogBatchLocked([
                MicroTechPeripheralManager.ignoredCallbackLogEntry(
                    callback: callback,
                    identifier: identifier,
                    service: service,
                    characteristic: characteristic,
                    reason: reason,
                    pendingOperation: pendingName
                ),
            ])
            condition.unlock()
            log(batch)
            return
        }
        var entries = MicroTechPeripheralManager.callbackLogEntries(
            callback: callback,
            identifier: identifier,
            service: service,
            characteristic: characteristic,
            error: error,
            value: nil,
            discoveredServiceUUIDs: discoveredServiceUUIDs,
            discoveredCharacteristicUUIDs: discoveredCharacteristicUUIDs
        )
        if
            callback == .notificationState,
            error == nil,
            let characteristic,
            !notificationValueAttemptSubmitted.contains(characteristic)
        {
            notificationValueAttemptSubmitted.insert(characteristic)
            entries.append(MicroTechPeripheralManager.notificationValueAttemptLogEntry(
                identifier: identifier,
                characteristic: characteristic
            ))
        }
        markCallbackArrivedLocked()
        let batch = makeLogBatchLocked(entries)
        condition.unlock()
        log(batch)
        finishCallback(operation: expectedOperation, error: error)
    }

    @discardableResult
    func handleValueCallback(
        identifier: UUID,
        characteristic: CBUUID,
        error: Error?,
        value: Data?,
        log: (MicroTechGattLogBatch) -> Void
    ) -> Data? {
        condition.lock()
        guard !logStreamCompleted else {
            condition.unlock()
            return nil
        }
        if sessionInvalidated {
            let invalidatedCallback: MicroTechGattCallback
            if invalidatedOperation == .read(characteristic) {
                invalidatedCallback = .read
            } else {
                invalidatedCallback = .notificationValue
            }
            let pendingName = pendingOperation?.name ?? invalidatedOperation?.name
            let batch = makeLogBatchLocked([
                MicroTechPeripheralManager.ignoredCallbackLogEntry(
                    callback: invalidatedCallback,
                    identifier: identifier,
                    service: nil,
                    characteristic: characteristic,
                    reason: "sessionInvalidated",
                    pendingOperation: pendingName
                ),
            ])
            condition.unlock()
            log(batch)
            return nil
        }
        let matchesRead = pendingOperation == .read(characteristic)
        if matchesRead, pendingCompleted || pendingCallbackArrived {
            let pendingName = pendingOperation?.name
            let reason = pendingCompleted ? "operationAlreadyCompleted" : "callbackAlreadyArrived"
            let batch = makeLogBatchLocked([
                MicroTechPeripheralManager.ignoredCallbackLogEntry(
                    callback: .read,
                    identifier: identifier,
                    service: nil,
                    characteristic: characteristic,
                    reason: reason,
                    pendingOperation: pendingName
                ),
            ])
            condition.unlock()
            log(batch)
            return nil
        }
        let submitsNotificationAttempt =
            !matchesRead &&
            pendingOperation == .notification(characteristic) &&
            !notificationValueAttemptSubmitted.contains(characteristic)
        if submitsNotificationAttempt {
            notificationValueAttemptSubmitted.insert(characteristic)
        }
        let completesRead = matchesRead && !pendingCallbackArrived
        if completesRead {
            markCallbackArrivedLocked()
        }
        let callback: MicroTechGattCallback = completesRead ? .read : .notificationValue
        var entries: [MicroTechGattLogEntry] = []
        if submitsNotificationAttempt {
            entries.append(MicroTechPeripheralManager.notificationValueAttemptLogEntry(
                identifier: identifier,
                characteristic: characteristic
            ))
        }
        entries.append(contentsOf: MicroTechPeripheralManager.callbackLogEntries(
            callback: callback,
            identifier: identifier,
            service: nil,
            characteristic: characteristic,
            error: error,
            value: value
        ))
        let batch = makeLogBatchLocked(entries)
        condition.unlock()
        log(batch)

        if completesRead {
            finishCallback(operation: .read(characteristic), error: error)
            return nil
        }
        guard error == nil else {
            return nil
        }
        return value
    }

    private func markCallbackArrivedLocked() {
        pendingCallbackArrived = true
    }

    private func finishCallback(operation: MicroTechGattOperation, error: Error?) {
        condition.lock()
        if
            !sessionInvalidated,
            pendingOperation == operation,
            pendingCallbackArrived,
            !pendingCompleted
        {
            completeLocked(error: pendingError ?? error)
        }
        condition.unlock()
    }

    private func completeLocked(error: Error?) {
        pendingError = error
        pendingCompleted = true
        condition.signal()
    }

    private func makeLogBatchLocked(
        _ entries: [MicroTechGattLogEntry],
        completesStream: Bool = false
    ) -> MicroTechGattLogBatch {
        defer { nextLogSequence += 1 }
        return MicroTechGattLogBatch(
            streamIdentifier: logStreamIdentifier,
            sequence: nextLogSequence,
            entries: entries,
            completesStream: completesStream
        )
    }

    private func operation(
        for callback: MicroTechGattCallback,
        service: CBUUID?,
        characteristic: CBUUID?
    ) -> MicroTechGattOperation? {
        switch callback {
        case .discoverServices:
            return service.map(MicroTechGattOperation.discoverServices)
        case .discoverCharacteristics:
            return service.map(MicroTechGattOperation.discoverCharacteristics)
        case .notificationState:
            return characteristic.map(MicroTechGattOperation.notification)
        case .write:
            return characteristic.map(MicroTechGattOperation.write)
        case .read, .notificationValue:
            return nil
        }
    }
}

public final class MicroTechPeripheralManager: NSObject, MicroTechPeripheralSession {
    public static let defaultOperationTimeout: TimeInterval = 8

    public weak var delegate: MicroTechPeripheralManagerDelegate?
    var willCancelConnection: ((UUID) -> Void)?
    var logHandler: ((String, MicroTechBluetoothLogType) -> Void)? {
        get { logQueue.handler }
        set { logQueue.handler = newValue }
    }

    public var deviceIdentifier: UUID {
        peripheral.identifier
    }

    public var deviceName: String {
        discoveredDeviceName ?? peripheral.name ?? "MicroTech LinX"
    }

    var isConnected: Bool {
        peripheral.state == .connected
    }

    private let peripheral: CBPeripheral
    private var discoveredDeviceName: String?
    private weak var centralManager: CBCentralManager?
    private let timeout: TimeInterval
    private let logQueue: MicroTechGattLogQueue
    private var characteristics: [CBUUID: CBCharacteristic] = [:]
    private let operationState = MicroTechGattOperationState()

    public convenience init(
        peripheral: CBPeripheral,
        centralManager: CBCentralManager,
        advertisedName: String? = nil,
        timeout: TimeInterval = MicroTechPeripheralManager.defaultOperationTimeout
    ) {
        self.init(
            peripheral: peripheral,
            centralManager: centralManager,
            advertisedName: advertisedName,
            timeout: timeout,
            logQueue: MicroTechGattLogQueue(
                label: "com.loopkit.MicroTechCGM.gatt-log.\(peripheral.identifier.uuidString)"
            )
        )
    }

    init(
        peripheral: CBPeripheral,
        centralManager: CBCentralManager,
        advertisedName: String? = nil,
        timeout: TimeInterval = MicroTechPeripheralManager.defaultOperationTimeout,
        logQueue: MicroTechGattLogQueue
    ) {
        self.peripheral = peripheral
        self.discoveredDeviceName = advertisedName
        self.centralManager = centralManager
        self.timeout = timeout
        self.logQueue = logQueue

        super.init()

        peripheral.delegate = self
    }

    func updateAdvertisedName(_ advertisedName: String?) {
        guard let advertisedName, !advertisedName.isEmpty else {
            return
        }
        discoveredDeviceName = advertisedName
    }

    public func configure() throws {
        do {
            try operationState.validateImmediateCommand()
        } catch {
            log(Self.synchronousFailureLogEntry(
                identifier: deviceIdentifier,
                operation: .discoverServices(MicroTechAidexProfile.serviceUUID),
                error: error
            ))
            throw error
        }
        let discoveredServiceUUIDs = peripheral.services?.map(\.uuid) ?? []
        if discoveredServiceUUIDs.contains(MicroTechAidexProfile.serviceUUID) {
            log(Self.discoveryCacheHitLogEntry(
                identifier: deviceIdentifier,
                operation: .discoverServices(MicroTechAidexProfile.serviceUUID),
                discoveredUUIDs: discoveredServiceUUIDs
            ))
        } else {
            try run(.discoverServices(MicroTechAidexProfile.serviceUUID)) {
                peripheral.discoverServices([MicroTechAidexProfile.serviceUUID])
            }
        }

        guard let service = peripheral.services?.first(where: { $0.uuid == MicroTechAidexProfile.serviceUUID }) else {
            log(Self.configureMissingAttributeLogEntry(
                identifier: deviceIdentifier,
                service: MicroTechAidexProfile.serviceUUID,
                characteristic: nil,
                discoveredUUIDs: peripheral.services?.map(\.uuid) ?? []
            ))
            throw MicroTechPeripheralManagerError.unknownService
        }

        let requiredCharacteristics = [
            MicroTechAidexProfile.f001UUID,
            MicroTechAidexProfile.f002UUID,
            MicroTechAidexProfile.f003UUID,
        ]

        let knownCharacteristicUUIDs = service.characteristics?.map(\.uuid) ?? []
        if requiredCharacteristics.allSatisfy(knownCharacteristicUUIDs.contains) {
            log(Self.discoveryCacheHitLogEntry(
                identifier: deviceIdentifier,
                operation: .discoverCharacteristics(service.uuid),
                discoveredUUIDs: knownCharacteristicUUIDs
            ))
        } else {
            try run(.discoverCharacteristics(service.uuid)) {
                peripheral.discoverCharacteristics(requiredCharacteristics, for: service)
            }
        }

        characteristics = Dictionary(
            uniqueKeysWithValues: (service.characteristics ?? [])
                .filter { requiredCharacteristics.contains($0.uuid) }
                .map { ($0.uuid, $0) }
        )

        let finalCharacteristicUUIDs = service.characteristics?.map(\.uuid) ?? []
        let missingCharacteristics = requiredCharacteristics.filter { characteristics[$0] == nil }
        for characteristic in missingCharacteristics {
            log(Self.configureMissingAttributeLogEntry(
                identifier: deviceIdentifier,
                service: service.uuid,
                characteristic: characteristic,
                discoveredUUIDs: finalCharacteristicUUIDs
            ))
        }
        if let characteristic = missingCharacteristics.first {
            throw MicroTechPeripheralManagerError.unknownCharacteristic(characteristic)
        }
    }

    public func subscribe(_ characteristic: CBUUID) throws {
        let operation = MicroTechGattOperation.notification(characteristic)
        let cbCharacteristic: CBCharacteristic
        do {
            try validateSession()
            cbCharacteristic = try requiredCharacteristic(characteristic)
        } catch {
            log(Self.synchronousFailureLogEntry(
                identifier: deviceIdentifier,
                operation: operation,
                error: error
            ))
            throw error
        }
        try run(operation) {
            peripheral.setNotifyValue(true, for: cbCharacteristic)
        }
    }

    public func write(_ value: Data, to characteristic: CBUUID) throws {
        let knownCharacteristic = characteristics[characteristic]
        let writeType: CBCharacteristicWriteType =
            knownCharacteristic?.properties.contains(.write) == true ? .withResponse : .withoutResponse
        var submitted = false
        do {
            try validateSession()
            let cbCharacteristic = try requiredCharacteristic(characteristic)
            if writeType == .withResponse {
                try run(
                    .write(characteristic),
                    attemptLogEntry: Self.writeAttemptLogEntry(
                        identifier: deviceIdentifier,
                        characteristic: characteristic,
                        value: value,
                        writeType: writeType
                    )
                ) {
                    peripheral.writeValue(value, for: cbCharacteristic, type: writeType)
                    submitted = true
                }
            } else {
                guard peripheral.state == .connected else {
                    throw MicroTechPeripheralManagerError.notConnected
                }
                try operationState.validateImmediateCommand()
                let entries = Self.writeWithoutResponseLogEntries(
                    identifier: deviceIdentifier,
                    characteristic: characteristic,
                    value: value
                )
                log(entries[0])
                peripheral.writeValue(value, for: cbCharacteristic, type: writeType)
                submitted = true
                log(entries[1])
            }
        } catch {
            if !submitted {
                log(Self.writeSynchronousFailureLogEntry(
                    identifier: deviceIdentifier,
                    characteristic: characteristic,
                    value: value,
                    writeType: writeType,
                    error: error
                ))
            }
            throw error
        }
    }

    public func read(_ characteristic: CBUUID) throws -> Data {
        let operation = MicroTechGattOperation.read(characteristic)
        let cbCharacteristic: CBCharacteristic
        do {
            try validateSession()
            cbCharacteristic = try requiredCharacteristic(characteristic)
        } catch {
            log(Self.synchronousFailureLogEntry(
                identifier: deviceIdentifier,
                operation: operation,
                error: error
            ))
            throw error
        }
        try run(operation) {
            peripheral.readValue(for: cbCharacteristic)
        }
        guard let value = cbCharacteristic.value else {
            throw MicroTechPeripheralManagerError.noValue(characteristic)
        }
        return value
    }

    public func disconnect() {
        guard operationState.requestDisconnect() else {
            return
        }
        operationState.completeLogStream(log: log)
        guard let centralManager, peripheral.state != .disconnected else {
            return
        }
        willCancelConnection?(deviceIdentifier)
        centralManager.cancelPeripheralConnection(peripheral)
    }

    func didDisconnect(error: Error?) {
        operationState.invalidateSession(error ?? MicroTechPeripheralManagerError.notConnected)
        operationState.completeLogStream(log: log)
        delegate?.microTechPeripheralManager(self, didDisconnectWith: error)
    }

    private func validateSession() throws {
        guard !operationState.isSessionInvalidated else {
            throw MicroTechPeripheralManagerError.notConnected
        }
    }

    private func requiredCharacteristic(_ uuid: CBUUID) throws -> CBCharacteristic {
        guard let characteristic = characteristics[uuid] else {
            throw MicroTechPeripheralManagerError.unknownCharacteristic(uuid)
        }
        return characteristic
    }

    private func run(
        _ command: MicroTechGattOperation,
        attemptLogEntry: MicroTechGattLogEntry? = nil,
        action: () -> Void
    ) throws {
        do {
            guard peripheral.state == .connected else {
                throw MicroTechPeripheralManagerError.notConnected
            }
            try operationState.begin(command)
        } catch {
            log(Self.synchronousFailureLogEntry(
                identifier: deviceIdentifier,
                operation: command,
                error: error
            ))
            throw error
        }

        log(attemptLogEntry ?? Self.gattAttemptLogEntry(identifier: deviceIdentifier, operation: command))
        action()

        guard try operationState.wait(
            timeout: timeout,
            onTimeout: { [weak self] in
                guard let self else {
                    return
                }
                log(Self.gattTimeoutLogEntry(identifier: deviceIdentifier, operation: command))
                disconnect()
            }
        ) == .completed else {
            throw MicroTechPeripheralManagerError.timeout
        }
    }

    private func log(_ entry: MicroTechGattLogEntry) {
        logQueue.submit(entry)
    }

    private func log(_ batch: MicroTechGattLogBatch) {
        logQueue.submit(batch)
    }

}

extension MicroTechPeripheralManager {
    static func callbackLogEntries(
        callback: MicroTechGattCallback,
        identifier: UUID,
        service: CBUUID?,
        characteristic: CBUUID?,
        error: Error?,
        value: Data?,
        discoveredServiceUUIDs: [CBUUID]? = nil,
        discoveredCharacteristicUUIDs: [CBUUID]? = nil
    ) -> [MicroTechGattLogEntry] {
        let target = targetFields(service: service, characteristic: characteristic)
        let base = "stage=gatt operation=\(callback.rawValue)"

        if let error {
            return [MicroTechGattLogEntry(
                message: "\(base) event=failed identifier=\(identifier) \(target) \(MicroTechDiagnosticLog.errorFields(error))",
                type: .error
            )]
        }

        switch callback {
        case .read, .notificationValue:
            guard let value else {
                return [MicroTechGattLogEntry(
                    message: "\(base) event=failed identifier=\(identifier) \(target) reason=missingValue",
                    type: .error
                )]
            }
            return [MicroTechGattLogEntry(
                message: "\(base) event=succeeded identifier=\(identifier) \(target) \(MicroTechDiagnosticLog.dataFields(lengthName: "valueLength", hexName: "valueHex", data: value))",
                type: .receive
            )]
        case .write:
            return [MicroTechGattLogEntry(
                message: "\(base) event=succeeded identifier=\(identifier) \(target)",
                type: .send
            )]
        case .discoverServices:
            return [MicroTechGattLogEntry(
                message: "\(base) event=succeeded identifier=\(identifier) \(target) discoveredServices=\(uuidList(discoveredServiceUUIDs ?? []))",
                type: .connection
            )]
        case .discoverCharacteristics:
            return [MicroTechGattLogEntry(
                message: "\(base) event=succeeded identifier=\(identifier) \(target) discoveredCharacteristics=\(uuidList(discoveredCharacteristicUUIDs ?? []))",
                type: .connection
            )]
        case .notificationState:
            return [MicroTechGattLogEntry(
                message: "\(base) event=succeeded identifier=\(identifier) \(target)",
                type: .connection
            )]
        }
    }

    static func gattAttemptLogEntry(
        identifier: UUID,
        operation: MicroTechGattOperation
    ) -> MicroTechGattLogEntry {
        MicroTechGattLogEntry(
            message: "stage=gatt operation=\(operation.name) event=attempted identifier=\(identifier) \(targetFields(service: operation.service, characteristic: operation.characteristic))",
            type: operation.name == "read" || operation.name == "notificationState" ? .send : .connection
        )
    }

    static func discoveryCacheHitLogEntry(
        identifier: UUID,
        operation: MicroTechGattOperation,
        discoveredUUIDs: [CBUUID]
    ) -> MicroTechGattLogEntry {
        let collectionName = operation.name == "discoverServices"
            ? "discoveredServices"
            : "discoveredCharacteristics"
        return MicroTechGattLogEntry(
            message: "stage=gatt operation=\(operation.name) event=cacheHit identifier=\(identifier) \(targetFields(service: operation.service, characteristic: operation.characteristic)) \(collectionName)=\(uuidList(discoveredUUIDs))",
            type: .connection
        )
    }

    static func configureMissingAttributeLogEntry(
        identifier: UUID,
        service: CBUUID,
        characteristic: CBUUID?,
        discoveredUUIDs: [CBUUID]
    ) -> MicroTechGattLogEntry {
        let reason = characteristic == nil ? "missingService" : "missingCharacteristic"
        let collectionName = characteristic == nil ? "discoveredServices" : "discoveredCharacteristics"
        return MicroTechGattLogEntry(
            message: "stage=gatt operation=configure event=failed identifier=\(identifier) \(targetFields(service: service, characteristic: characteristic)) reason=\(reason) \(collectionName)=\(uuidList(discoveredUUIDs))",
            type: .error
        )
    }

    static func synchronousFailureLogEntry(
        identifier: UUID,
        operation: MicroTechGattOperation,
        error: Error
    ) -> MicroTechGattLogEntry {
        MicroTechGattLogEntry(
            message: "stage=gatt operation=\(operation.name) event=failed identifier=\(identifier) \(targetFields(service: operation.service, characteristic: operation.characteristic)) reason=synchronousFailure \(MicroTechDiagnosticLog.errorFields(error))",
            type: .error
        )
    }

    static func gattTimeoutLogMessage(
        identifier: UUID,
        operation: MicroTechGattOperation
    ) -> String {
        gattTimeoutLogEntry(identifier: identifier, operation: operation).message
    }

    static func writeAttemptLogEntry(
        identifier: UUID,
        characteristic: CBUUID,
        value: Data,
        writeType: CBCharacteristicWriteType
    ) -> MicroTechGattLogEntry {
        return MicroTechGattLogEntry(
            message: "stage=gatt operation=write event=attempted identifier=\(identifier) service=nil characteristic=\(characteristic.uuidString) writeType=\(writeTypeName(writeType)) \(MicroTechDiagnosticLog.dataFields(lengthName: "payloadLength", hexName: "payloadHex", data: value))",
            type: .send
        )
    }

    static func writeSynchronousFailureLogEntry(
        identifier: UUID,
        characteristic: CBUUID,
        value: Data,
        writeType: CBCharacteristicWriteType,
        error: Error
    ) -> MicroTechGattLogEntry {
        MicroTechGattLogEntry(
            message: "stage=gatt operation=write event=failed identifier=\(identifier) service=nil characteristic=\(characteristic.uuidString) writeType=\(writeTypeName(writeType)) \(MicroTechDiagnosticLog.dataFields(lengthName: "payloadLength", hexName: "payloadHex", data: value)) \(MicroTechDiagnosticLog.errorFields(error))",
            type: .error
        )
    }

    static func notificationValueAttemptLogEntry(
        identifier: UUID,
        characteristic: CBUUID
    ) -> MicroTechGattLogEntry {
        MicroTechGattLogEntry(
            message: "stage=gatt operation=notificationValue event=attempted identifier=\(identifier) service=nil characteristic=\(characteristic.uuidString)",
            type: .send
        )
    }

    static func ignoredCallbackLogEntry(
        callback: MicroTechGattCallback,
        identifier: UUID,
        service: CBUUID?,
        characteristic: CBUUID?,
        reason: String,
        pendingOperation: String?
    ) -> MicroTechGattLogEntry {
        MicroTechGattLogEntry(
            message: "stage=gatt operation=\(callback.rawValue) event=ignored identifier=\(identifier) \(targetFields(service: service, characteristic: characteristic)) reason=\(reason) pendingOperation=\(pendingOperation ?? "nil")",
            type: .error
        )
    }

    static func writeWithoutResponseLogEntries(
        identifier: UUID,
        characteristic: CBUUID,
        value: Data
    ) -> [MicroTechGattLogEntry] {
        [
            writeAttemptLogEntry(
                identifier: identifier,
                characteristic: characteristic,
                value: value,
                writeType: .withoutResponse
            ),
            MicroTechGattLogEntry(
                message: "stage=gatt operation=write event=submitted identifier=\(identifier) service=nil characteristic=\(characteristic.uuidString) writeType=withoutResponse noCallback=true",
                type: .send
            ),
        ]
    }

    private static func gattTimeoutLogEntry(
        identifier: UUID,
        operation: MicroTechGattOperation
    ) -> MicroTechGattLogEntry {
        MicroTechGattLogEntry(
            message: "stage=gatt event=timeout identifier=\(identifier) pendingOperation=\(operation.name) \(targetFields(service: operation.service, characteristic: operation.characteristic))",
            type: .error
        )
    }

    private static func targetFields(service: CBUUID?, characteristic: CBUUID?) -> String {
        "service=\(service?.uuidString ?? "nil") characteristic=\(characteristic?.uuidString ?? "nil")"
    }

    private static func writeTypeName(_ writeType: CBCharacteristicWriteType) -> String {
        switch writeType {
        case .withResponse:
            return "withResponse"
        case .withoutResponse:
            return "withoutResponse"
        @unknown default:
            return "unknown"
        }
    }

    private static func uuidList(_ uuids: [CBUUID]) -> String {
        "[\(uuids.map(\.uuidString).sorted().joined(separator: ","))]"
    }
}

extension MicroTechPeripheralManager: CBPeripheralDelegate {
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        operationState.handleOperationCallback(
            callback: .discoverServices,
            identifier: deviceIdentifier,
            service: MicroTechAidexProfile.serviceUUID,
            characteristic: nil,
            error: error,
            discoveredServiceUUIDs: peripheral.services?.map(\.uuid),
            log: log
        )
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        operationState.handleOperationCallback(
            callback: .discoverCharacteristics,
            identifier: deviceIdentifier,
            service: service.uuid,
            characteristic: nil,
            error: error,
            discoveredCharacteristicUUIDs: service.characteristics?.map(\.uuid),
            log: log
        )
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        operationState.handleOperationCallback(
            callback: .notificationState,
            identifier: deviceIdentifier,
            service: nil,
            characteristic: characteristic.uuid,
            error: error,
            log: log
        )
    }

    public func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        operationState.handleOperationCallback(
            callback: .write,
            identifier: deviceIdentifier,
            service: nil,
            characteristic: characteristic.uuid,
            error: error,
            log: log
        )
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let value = operationState.handleValueCallback(
            identifier: deviceIdentifier,
            characteristic: characteristic.uuid,
            error: error,
            value: characteristic.value,
            log: log
        ) else {
            return
        }
        delegate?.microTechPeripheralManager(self, didUpdateValue: value, for: characteristic.uuid)
    }
}
