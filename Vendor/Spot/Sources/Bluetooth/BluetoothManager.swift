//
//  BluetoothManager.swift
//
//
//  Created by Leon Böttger on 15.04.22.
//

import CoreBluetooth
import CoreData
import CryptoSwift
import Combine
import SwiftUI

/// Wrapper class for CoreBluetooth actions
open class BluetoothManager: NSObject, CBPeripheralDelegate, CBCentralManagerDelegate, ObservableObject {
    /// The initializer
    override private init() {
        super.init()

        if (TokenManager.sharedInstance.aasToken != nil) {
            startCentralManager()
        }
    }

    /// The shared instance
    static var sharedInstance = BluetoothManager()

    /// The CoreBluetooth restore identifier
    private let restoreID = "spot-bluetooth-manager"

    /// The requests queue
    private var requests = [BluetoothRequest]()
    private var writeReadStarted = Set<UUID>()
    private var firmwareReservations = Set<UUID>()

    /// The central manager
    var centralManager: CBCentralManager?

    /// Keeps a reference to all peripherals to keep receiving delegate calls - use `peripheralsSyncronizeDataQueue` to access
    private var peripherals: [String: BluetoothTempData] = [:]

    /// Shows if the manager is scanning
    @Published var scanning = false

    /// Shows if Bluetooth is turned on
    @Published var turnedOn = false

    /// True if the app is using fast scan with duplicates for precision finding
    @Published var isUsingFastScan = false

    /// Array of devices to which we can connect when using fast scan
    @Published var allowedConnectionUUIDsFastScan = [UUID]()

    /// The timer to turn on/off scanning periodically
    let timer = BluetoothManagerTimer.sharedInstance

    /// Reference to settings
    @ObservedObject var settings = Settings.sharedInstance

    /// Determines if the Bluetooth Manager should only search for this given device.
    @Published var rssiScanForDevice: RSSIScan? = nil

    /// The serialized background queue of the bluetooth manager.
    private let bluetoothQueue = DispatchQueue(label: "bluetoothQueue")

    /// Background queue for access to `peripherals`
    let peripheralsSyncronizeDataQueue = DispatchQueue(label: "peripheralsSyncronizeDataQueue")

    /// The set of recently seen EIDs
    @Published var recentlySeenEids: Set<Data> = []

    /// Initializes the central manager.
    func startCentralManager() {
        bluetoothQueue.async { [self] in
            if centralManager == nil {
                let manager = CBCentralManager(delegate: self, queue: bluetoothQueue, options: [CBCentralManagerOptionRestoreIdentifierKey: restoreID])
                centralManager = manager
                centralManagerDidUpdateState(manager)
            }
        }
    }

    /// Returns (and creates) the temporary Bluetooth data for the specified Bluetooth UUID.
    func getBluetoothData(bluetoothID: String) -> BluetoothTempData {
        peripheralsSyncronizeDataQueue.sync {
            if let data = peripherals[bluetoothID] {
                return data
            }

            peripherals[bluetoothID] = BluetoothTempData(identifier: bluetoothID)

            return peripherals[bluetoothID]!
        }
    }

    private func getServiceData(advertisementData: [String: Any], key: String) -> Data? {
        let servData = advertisementData[CBAdvertisementDataServiceDataKey]

        if let servData = servData as? [CBUUID: Data] {
            if let data = servData[CBUUID(string: key)] {
                return data
            }
        }
        return nil
    }

    /// Stores the data of a CBPeripheral in a BluetoothTempData object and returns it.
    private func storePeripheral(peripheral: CBPeripheral) -> BluetoothTempData {
        peripheralsSyncronizeDataQueue.sync {
            let identifier = peripheral.identifier.uuidString

            if peripherals[identifier] == nil {
                peripherals[identifier] = BluetoothTempData(identifier: identifier)
            }

            if peripherals[identifier]!.peripheral_background != peripheral {
                peripherals[identifier]!.peripheral_background = peripheral
                peripheral.delegate = self
            }

            peripherals[identifier]!.last_update_background = Date()

            return peripherals[identifier]!
        }
    }

    // Serialize the handoff to the dedicated Motorola/SMP transport. Background
    // scans may continue, but must never reconnect or enqueue commands to this tag.
    func reserveForFirmware(_ id: UUID) async {
        await withCheckedContinuation { continuation in
            bluetoothQueue.async { [self] in
                firmwareReservations.insert(id)
                for request in requests.filter({ $0.deviceID == id.uuidString }) {
                    finishRequest(request: request, withState: .Failure, peripheral: nil)
                }
                if let peripheral = centralManager?.retrievePeripherals(withIdentifiers: [id]).first {
                    centralManager?.cancelPeripheralConnection(peripheral)
                }
                continuation.resume()
            }
        }
    }
    func releaseFromFirmware(_ id: UUID) {
        bluetoothQueue.async { [self] in firmwareReservations.remove(id) }
    }

    /// Adds a bluetooth request to the queue. -- This needs to run on MAIN thread!
    func addRequest(request: BluetoothRequest) {
        bluetoothQueue.async { [self] in
            if let id = UUID(uuidString: request.deviceID), firmwareReservations.contains(id) {
                request.callback(.Failure, nil); return
            }
            if !turnedOn {
                finishRequest(request: request, withState: .Timeout, peripheral: nil)
                return
            }

            // retrieve the peripheral
            if let id = UUID(uuidString: request.deviceID), let peripheral = centralManager?.retrievePeripherals(withIdentifiers: [id]).first {
                // add to queue
                requests.append(request)

                // add delegate
                let device = storePeripheral(peripheral: peripheral)

                // already connected
                if device.connected_background, let centralManager {
                    self.centralManager(centralManager, didConnect: peripheral)
                } else {
                    if isUsingFastScan {
                        // Check if the we are allowed to connect to this device
                        if !allowedConnectionUUIDsFastScan.contains(peripheral.identifier) {
                            request.callback(.Failure, nil)
                            return
                        }
                    }
                    // connect to peripheral
                    centralManager?.connect(peripheral)
                }
            }

            // we did not find the peripheral
            else {
                request.callback(.Failure, nil)
            }

            // After 10 seconds, we send a timeout to the callback
            bluetoothQueue.asyncAfter(deadline: .now() + 15) { [self] in
                if requests.contains(where: { $0.id == request.id }) {
                    finishRequest(request: request, withState: .Timeout, peripheral: nil)
                }
            }
        }
    }

    /// Called if state of the central manager changed.
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        // Bluetooth is turned off
        if !isSimulator(), central.state != CBManagerState.poweredOn {
            DispatchQueue.main.async {
                withAnimation {
                    self.turnedOn = false
                }
            }

            stopScan()
        }

        // Bluetooth is turned on
        else {
            DispatchQueue.main.async { [self] in
                withAnimation {
                    self.turnedOn = true
                }

                if !scanning, (TokenManager.sharedInstance.aasToken != nil) {
                    startScan()
                }
            }
        }
    }

    /// Cancels all connections to peripherals.
    func cancelAllConnections() {
        if turnedOn {
            // disconnect from everything
            peripheralsSyncronizeDataQueue.sync {
                for device in peripherals.values {
                    if let peripheral = device.peripheral_background {
                        centralManager?.cancelPeripheralConnection(peripheral)
                    }
                }
            }
        }
    }

    /// Starts a scan. Also stops the current scan and switches to the correct scan (background, foreground).
    func startScan(duplicates: Bool = false, services: [CBUUID]? = nil) {
        bluetoothQueue.async { [self] in
            if turnedOn {
                centralManager?.stopScan()

                let findMyDeviceUUID = CBUUID(string: Constants.FindMyDeviceService)
                let fastPairUUID = CBUUID(string: Constants.FastPairService)

                let uuids = [findMyDeviceUUID, fastPairUUID]

                if settings.isBackground {
                    cancelAllConnections()

                    if settings.backgroundScanning {
                        /// CBCentralManagerScanOptionAllowDuplicatesKey is ignored in background scans: https://developer.apple.com/library/archive/documentation/NetworkingInternetWeb/Conceptual/CoreBluetooth_concepts/CoreBluetoothBackgroundProcessingForIOSApps/PerformingTasksWhileYourAppIsInTheBackground.html
                        /// Multiple discovery events are coalesced into one
                        /// It is therefore not possible to detect if the Chipolo (without Find My) tracker is following us.
                        centralManager?.scanForPeripherals(withServices: uuids, options: [CBCentralManagerScanOptionAllowDuplicatesKey: duplicates])
                    }
                } else {
                    if duplicates {
                        // When using fast scan we don't want connections in the background
                        cancelAllConnections()
                    }
                    centralManager?.scanForPeripherals(withServices: services ?? uuids, options: [CBCentralManagerScanOptionAllowDuplicatesKey: duplicates])
                }

                DispatchQueue.main.async {
                    withAnimation {
                        self.scanning = true
                    }
                }
            }
        }
    }

    /// Stops the current scan.
    func stopScan() {
        bluetoothQueue.async { [self] in
            if scanning {
                centralManager?.stopScan()

                DispatchQueue.main.async {
                    withAnimation {
                        self.scanning = false
                    }
                }
            }
        }
    }

    /// Resets the Bluetooth manager.
    func reset() {
        bluetoothQueue.async { [self] in
            stopScan()

            cancelAllConnections()

            requests.removeAll()

            peripheralsSyncronizeDataQueue.sync {
                peripherals.removeAll()
            }

            startScan()
        }
    }

    /// Enables the fast scan which allowed advertisement duplicates. For better performance, you need to specify a Bluetooth device UUID or a service to search for. The service needs to be included in all advertisement packets.
    func enableFastScan(for device: RSSIScan, allowedUUIDs: [UUID]) {
        bluetoothQueue.async { [self] in
            DispatchQueue.main.async { [self] in
                allowedConnectionUUIDsFastScan = allowedUUIDs
                isUsingFastScan = true
                rssiScanForDevice = device

                if let service = device.service {
                    startScan(duplicates: true, services: [CBUUID(string: service)])
                }
                if let id = device.bluetoothDevice {
                    startScan(duplicates: true)
                }
            }
        }
    }

    /// Disables the fast scan which allowed advertisement duplicates.
    func disableFastScan() {
        bluetoothQueue.async { [self] in
            DispatchQueue.main.async { [self] in
                rssiScanForDevice = nil
                isUsingFastScan = false
                allowedConnectionUUIDsFastScan = []
                startScan()
            }
        }
    }

    /// Returns if the manager is currently only scanning for one device (type)
    func isFastScanning() -> Bool {
        rssiScanForDevice != nil
    }

    /// Called if state of central manager is restored.
    public func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        if let _ = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] {
            centralManagerDidUpdateState(central)
        }
    }

    /// Found new device via scan
    public func centralManager(_: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard !firmwareReservations.contains(peripheral.identifier) else { return }
        if let id = rssiScanForDevice?.bluetoothDevice, peripheral.identifier.uuidString != id {
            return
        }

        // first, add peripheral to array
        let device = storePeripheral(peripheral: peripheral)

        device.rssi_background = Double(truncating: RSSI)

        if !advertisementData.isEmpty {
            device.advertisementData_background = advertisementData
        }

        if let serviceData = getServiceData(advertisementData: advertisementData, key: Constants.FindMyDeviceService),
           serviceData.count == 22 || serviceData.count == 21
        { // hashed flags may be omitted

            let bluetoothId = peripheral.identifier.uuidString

            let eid = serviceData.subdata(in: 1 ..< 21)
            let unwantedTrackingMode = serviceData.subdata(in: 0 ..< 1)

            if unwantedTrackingMode == Data([0x40]) {
                device.unwanted_tracking_mode_background = false
            }
            if unwantedTrackingMode == Data([0x41]) {
                device.unwanted_tracking_mode_background = true
            }

            DispatchQueue.main.async {
                self.recentlySeenEids.insert(eid)
            }

            if let truncatedEidInfo = TruncatedEidCache.sharedInstance.lookup(truncatedEid: TruncatedEID.fromEID(eid)), let listedDevices = Settings.sharedInstance.devicesList?.filter({ $0.canonicDeviceId == truncatedEidInfo.canonicDeviceId }) {
                for listedDevice in listedDevices {
                    if serviceData.count == 22, let identityKey = listedDevice.eik {
                        let flags = serviceData.subdata(in: 21 ..< 22)
                        let curveType = listedDevice.curveType

                        do {
                            let currentAdvertisementTime = truncatedEidInfo.timestamp
                            let trackerPairingTime = listedDevice.pairDate.unixTime

                            let trackerTimeCounter = Int32(currentAdvertisementTime - trackerPairingTime)

                            let r = try ensureDataLength(EIDGenerator.calculateR(identityKey: identityKey, timestamp: trackerTimeCounter, curveType: curveType).data, length: curveType.length)
                            let hashedR = SHA256.hash(data: r)

                            // get LSB of hashedR
                            if let lsb = hashedR.last {
                                // result is flags XOR lsb
                                let result: [Bit] = (flags[0] ^ lsb).bits()

                                // extract bit 5 and 6
                                let bit5 = result[5]
                                let bit6 = result[6]

                                var batteryState = BatteryState.Unknown

                                if bit5 == .zero, bit6 == .one {
                                    batteryState = .Normal
                                }

                                if bit5 == .one, bit6 == .zero {
                                    batteryState = .Low
                                }

                                if bit5 == .one, bit6 == .one {
                                    batteryState = .Critical
                                }

                                if batteryState != .Unknown, batteryState != listedDevice.batteryState {
                                    DispatchQueue.main.async {
                                        listedDevice.batteryState = batteryState
                                    }
                                }
                            }
                        } catch {}
                    }

                    // Detected owned device => refresh bluetooth id
                    if listedDevice.bluetoothData == nil || listedDevice.bluetoothData?.identifier_background != bluetoothId {
                        DispatchQueue.main.async {
                            withAnimation(.smooth) {
                                listedDevice.bluetoothData = device
                            }
                        }
                    }

                    if device.unwanted_tracking_mode_background, Settings.sharedInstance.automaticallyDisableUnwantedTrackingMode {
                        DisableUnwantedTrackingModeOperation.perform(device: listedDevice, bluetoothId: bluetoothId)
                    } else {
                        listedDevice.uploadLocationIfNecessary()
                    }
                }
            }
        }
    }

    /// Connected successfully to device
    public func centralManager(_: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard !firmwareReservations.contains(peripheral.identifier) else { centralManager?.cancelPeripheralConnection(peripheral); return }
        let device = storePeripheral(peripheral: peripheral)

        device.connected_background = true

        for request in requests {
            if request.deviceID == peripheral.identifier.uuidString {
                // we are done with the request
                if request.operation == .ProbeConnect {
                    finishRequest(request: request, withState: .Success, peripheral: peripheral)
                } else {
                    if let service = request.serviceID {
                        if let services = peripheral.services, services.contains(where: { $0.uuid.uuidString == service }) {
                            discoveredServices(peripheral: peripheral)
                        } else {
                            peripheral.discoverServices([CBUUID(string: service)])
                        }
                    }
                }
            }
        }
    }

    /// Refreshed RSSI of device
    public func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error _: Error?) {
        if let cm = centralManager {
            centralManager(cm, didDiscover: peripheral, advertisementData: [:], rssi: RSSI)
        }
    }

    /// Disconnected from device
    public func centralManager(_: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error _: Error?) {
        let device = storePeripheral(peripheral: peripheral)

        device.connected_background = false

        // If we still have a request for this device, try to reconnect
        if peripheralIsRequested(peripheral: peripheral) {
            centralManager?.connect(peripheral)
        }
    }

    /// Discovered services of device
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices _: Error?) {
        discoveredServices(peripheral: peripheral)
    }

    /// Modified services of device
    public func peripheral(_ peripheral: CBPeripheral, didModifyServices _: [CBService]) {
        discoveredServices(peripheral: peripheral)
    }

    /// Handles requests when manager discovered services
    private func discoveredServices(peripheral: CBPeripheral) {
        for request in requests {
            if request.deviceID == peripheral.identifier.uuidString {
                if let service = peripheral.services?.first(where: { $0.uuid.uuidString == request.serviceID }) {
                    if request.operation == .ProbeService {
                        finishRequest(request: request, withState: .Success, peripheral: peripheral)
                    } else if let characteristic = request.characteristicID {
                        peripheral.discoverCharacteristics([CBUUID(string: characteristic)], for: service)
                    } else {
                        finishRequest(request: request, withState: .Failure, peripheral: peripheral)
                    }
                }
            }
        }
    }

    /// Discoverered characteristics of service
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error _: Error?) {
        for request in requests {
            if request.deviceID == peripheral.identifier.uuidString {
                if let characteristic = service.characteristics?.first(where: { $0.uuid.uuidString == request.characteristicID }) {
                    // we want to be notified if read/write operation was successful
                    if !characteristic.isNotifying, characteristic.properties.contains(.notify) || characteristic.properties.contains(.indicate) {
                        peripheral.setNotifyValue(true, for: characteristic)
                    }

                    // read data
                    if request.operation == .ReadCharacteristic {
                        peripheral.readValue(for: characteristic)
                    }

                    // write data
                    if let data = request.data,
                       request.operation == .WriteCharacteristic || (request.operation == .WriteReadCharacteristic && characteristic.isNotifying) {
                        if request.operation == .WriteReadCharacteristic {
                            guard writeReadStarted.insert(request.id).inserted else { continue }
                        }
                        let noResponse = characteristic.properties.contains(.writeWithoutResponse)
                        peripheral.writeValue(data, for: characteristic, type: noResponse ? .withoutResponse : .withResponse)

                        bluetoothQueue.asyncAfter(deadline: .now() + 1) { [self] in
                            guard request.operation == .WriteCharacteristic else { return }
                            if noResponse {
                                // Assume that everything worked
                                finishRequest(request: request, withState: .Success, peripheral: peripheral)
                            } else {
                                // If write request is not acknowledged after one second, we assume that it was unsuccessful
                                if requests.contains(where: { $0.id == request.id }) {
                                    finishRequest(request: request, withState: .Failure, peripheral: peripheral)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        for request in requests where request.deviceID == peripheral.identifier.uuidString &&
            request.characteristicID == characteristic.uuid.uuidString && request.operation == .WriteReadCharacteristic && !writeReadStarted.contains(request.id) {
            guard error == nil, characteristic.isNotifying, let data = request.data else {
                finishRequest(request: request, withState: .Failure, peripheral: peripheral); continue
            }
            writeReadStarted.insert(request.id)
            peripheral.writeValue(data, for: characteristic,
                type: characteristic.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse)
        }
    }

    /// Called if characteristic written
    public func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        for request in requests {
            if request.deviceID == peripheral.identifier.uuidString, request.characteristicID == characteristic.uuid.uuidString, request.operation == .WriteCharacteristic {
                if let error {
                    finishRequest(request: request, withState: .Failure, peripheral: peripheral)
                } else {
                    finishRequest(request: request, withState: .Success, peripheral: peripheral)
                }
            }
        }
    }

    /// Called if read value of characteristic
    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        for request in requests {
            if request.deviceID == peripheral.identifier.uuidString, request.characteristicID == characteristic.uuid.uuidString, request.operation == .ReadCharacteristic || request.operation == .WriteReadCharacteristic {
                if let error {
                    finishRequest(request: request, withState: .Failure, peripheral: peripheral)
                } else {
                    finishRequest(request: request, withState: .Success, data: characteristic.value, peripheral: peripheral)
                }
            }
        }
    }

    /// Performs the callback of the request and deletes it
    private func finishRequest(request: BluetoothRequest, withState: BluetoothRequestState, data: Data? = nil, peripheral: CBPeripheral?) {
        request.callback(withState, data)
        requests.removeAll(where: { request.id == $0.id })
        writeReadStarted.remove(request.id)

        if let peripheral, !request.stayConnected {
            centralManager?.cancelPeripheralConnection(peripheral)
        }
    }

    /// Returns true if there is a request for the given peripheral
    private func peripheralIsRequested(peripheral: CBPeripheral) -> Bool {
        requests.contains(where: { $0.deviceID == peripheral.identifier.uuidString })
    }
}

/// Used to determine for what the Bluetooth Manager should search for. Only use `service` OR `bluetoothDevice`, not both.
struct RSSIScan {
    /// Bluetooth service to search for. The service needs to be included in all advertisement packets.
    var service: String?

    /// Bluetooth device UUID to search for.
    var bluetoothDevice: String?
}
