import CoreBluetooth
import Foundation

public protocol MicroTechBluetoothManagerDelegate: AnyObject {
    func microTechBluetoothManager(_ manager: MicroTechBluetoothManager, shouldConnectToDeviceName deviceName: String, identifier: UUID) -> Bool
    func microTechBluetoothManager(_ manager: MicroTechBluetoothManager, didReady peripheralSession: MicroTechPeripheralSession)
    func microTechBluetoothManager(_ manager: MicroTechBluetoothManager, didReceive value: Data, for characteristic: CBUUID, session: MicroTechPeripheralSession)
    func microTechBluetoothManager(_ manager: MicroTechBluetoothManager, didDisconnect session: MicroTechPeripheralSession)
    func microTechBluetoothManager(_ manager: MicroTechBluetoothManager, didFailWith error: Error)
}

public final class MicroTechBluetoothManager: NSObject {
    public weak var delegate: MicroTechBluetoothManagerDelegate?

    public private(set) var activeRemoteIdentifier: UUID?

    private let managerQueue = DispatchQueue(label: "com.loopkit.MicroTechCGM.bluetoothManager")
    private var centralManager: CBCentralManager!
    private var managedPeripherals: [UUID: MicroTechPeripheralManager] = [:]
    private var activePeripheralManager: MicroTechPeripheralManager? {
        didSet {
            activeRemoteIdentifier = activePeripheralManager?.deviceIdentifier
        }
    }

    public override init() {
        super.init()

        managerQueue.sync {
            centralManager = CBCentralManager(
                delegate: self,
                queue: managerQueue,
                options: [CBCentralManagerOptionRestoreIdentifierKey: "com.loopkit.MicroTechCGM"]
            )
        }
    }

    public var isScanning: Bool {
        managerQueue.sync {
            centralManager.isScanning
        }
    }

    public var isConnected: Bool {
        managerQueue.sync {
            activePeripheralManager != nil
        }
    }

    public func scan(remoteIdentifier: UUID? = nil) {
        managerQueue.async {
            self.activeRemoteIdentifier = remoteIdentifier ?? self.activeRemoteIdentifier
            self.scanIfReady()
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
                manager.disconnect()
            }
        }
    }

    public func forgetPeripheral() {
        managerQueue.async {
            self.activePeripheralManager = nil
        }
    }

    private func scanIfReady() {
        guard centralManager.state == .poweredOn else {
            return
        }

        if let identifier = activeRemoteIdentifier,
           let peripheral = centralManager.retrievePeripherals(withIdentifiers: [identifier]).first
        {
            connectIfNeeded(peripheral, advertisedName: peripheral.name)
            return
        }

        for peripheral in centralManager.retrieveConnectedPeripherals(withServices: [MicroTechAidexProfile.serviceUUID]) {
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
        centralManager.scanForPeripherals(withServices: [MicroTechAidexProfile.serviceUUID], options: nil)
    }

    private func stopScanningOnQueue() {
        if centralManager.isScanning {
            centralManager.stopScan()
        }
    }

    private func connectIfNeeded(_ peripheral: CBPeripheral, advertisedName: String?) {
        let deviceName = advertisedName ?? peripheral.name ?? ""
        let shouldConnectByIdentifier = activeRemoteIdentifier == peripheral.identifier
        let isBindableName = deviceName.localizedCaseInsensitiveContains("LinX") ||
            deviceName.localizedCaseInsensitiveContains("AiDEX")

        guard shouldConnectByIdentifier || isBindableName else {
            return
        }

        if !shouldConnectByIdentifier,
           delegate?.microTechBluetoothManager(self, shouldConnectToDeviceName: deviceName, identifier: peripheral.identifier) == false
        {
            return
        }

        let manager = managedPeripherals[peripheral.identifier] ?? MicroTechPeripheralManager(
            peripheral: peripheral,
            centralManager: centralManager
        )
        manager.delegate = self
        managedPeripherals[peripheral.identifier] = manager
        activePeripheralManager = manager

        if peripheral.state != .connected && peripheral.state != .connecting {
            centralManager.connect(peripheral)
        }
    }
}

extension MicroTechBluetoothManager: CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard central.state == .poweredOn else {
            stopScanningOnQueue()
            return
        }
        scanIfReady()
    }

    public func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        guard let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] else {
            return
        }
        for peripheral in peripherals {
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
        connectIfNeeded(peripheral, advertisedName: advertisedName)
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard let manager = managedPeripherals[peripheral.identifier] else {
            return
        }

        DispatchQueue.global(qos: .utility).async {
            do {
                try manager.configure()
                self.managerQueue.async {
                    self.stopScanningOnQueue()
                    self.delegate?.microTechBluetoothManager(self, didReady: manager)
                }
            } catch {
                self.managerQueue.async {
                    self.delegate?.microTechBluetoothManager(self, didFailWith: error)
                }
            }
        }
    }

    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        if let error {
            delegate?.microTechBluetoothManager(self, didFailWith: error)
        }
        managedPeripherals.removeValue(forKey: peripheral.identifier)
        if activePeripheralManager?.deviceIdentifier == peripheral.identifier {
            activePeripheralManager = nil
        }
    }

    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard let manager = managedPeripherals[peripheral.identifier] else {
            return
        }
        manager.didDisconnect(error: error)
        managedPeripherals.removeValue(forKey: peripheral.identifier)
        if activePeripheralManager?.deviceIdentifier == peripheral.identifier {
            activePeripheralManager = nil
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
            delegate?.microTechBluetoothManager(self, didFailWith: error)
        }
    }
}
