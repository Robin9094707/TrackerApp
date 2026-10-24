import Foundation
import CoreBluetooth
import SpotIntegration

/// Dedicated read-only vendor connection. It never scans for arbitrary tags and
/// never writes update data. The SMP transport takes over after this closes.
@MainActor
// All delegate callbacks are delivered on the explicitly selected main queue.
final class MotorolaBLEInspector: NSObject, @preconcurrency CBCentralManagerDelegate, @preconcurrency CBPeripheralDelegate {
    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var command: CBCharacteristic?
    private var response: CBCharacteristic?
    private var target: MotorolaFirmwareTarget?
    private var pending: CheckedContinuation<MotorolaHardwareInfo, Error>?
    private var timeout: Task<Void, Never>?
    private var step: UInt8 = 4
    private var modelID = ""
    private var firmware = ""
    private var hardware = ""

    func read(_ target: MotorolaFirmwareTarget) async throws -> MotorolaHardwareInfo {
        guard pending == nil else { throw MotorolaFirmwareError.invalid("Eine Motorola-Verbindung läuft bereits.") }
        self.target = target
        return try await withCheckedThrowingContinuation { continuation in
            pending = continuation
            timeout = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(25)) } catch { return }
                self?.finish(.failure(MotorolaFirmwareError.invalid("Der Moto Tag antwortet nicht. Näher herangehen und die Motorola-App auf anderen Geräten schließen.")))
            }
            central = CBCentralManager(delegate: self, queue: .main)
        }
    }
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard pending != nil else { return }
        switch central.state {
        case .poweredOn:
            guard peripheral == nil, let target,
                  let device = central.retrievePeripherals(withIdentifiers: [target.peripheralID]).first else {
                if peripheral == nil { finish(.failure(MotorolaFirmwareError.invalid("Der ausgewählte Tag ist nicht mehr erreichbar."))) }
                return
            }
            peripheral = device; device.delegate = self; central.connect(device)
        case .unknown, .resetting: break
        default: finish(.failure(MotorolaFirmwareError.invalid("Bluetooth ist ausgeschaltet oder für RJ Tracker nicht freigegeben.")))
        }
    }
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([CBUUID(string: MotorolaReadProtocol.service), CBUUID(string: "8D53DC1D-1DB7-4CD3-868B-8A527460AA84")])
    }
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        finish(.failure(error ?? MotorolaFirmwareError.invalid("Verbindung zum Moto Tag fehlgeschlagen.")))
    }
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        if pending != nil { finish(.failure(error ?? MotorolaFirmwareError.invalid("Verbindung zum Moto Tag wurde getrennt."))) }
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error { finish(.failure(error)); return }
        guard let services = peripheral.services,
              let vendor = services.first(where: { $0.uuid == CBUUID(string: MotorolaReadProtocol.service) }) else {
            finish(.failure(MotorolaFirmwareError.invalid("Motorola-Geräteinformationen werden von dieser Firmware nicht angeboten."))); return
        }
        if target?.model == .firstGeneration && !services.contains(where: { $0.uuid == CBUUID(string: "8D53DC1D-1DB7-4CD3-868B-8A527460AA84") }) {
            finish(.failure(MotorolaFirmwareError.invalid("Dieser Tag bietet den benötigten SMP-Updatedienst nicht an."))); return
        }
        peripheral.discoverCharacteristics([CBUUID(string: MotorolaReadProtocol.command), CBUUID(string: MotorolaReadProtocol.response)], for: vendor)
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error { finish(.failure(error)); return }
        command = service.characteristics?.first { $0.uuid == CBUUID(string: MotorolaReadProtocol.command) }
        response = service.characteristics?.first { $0.uuid == CBUUID(string: MotorolaReadProtocol.response) }
        guard let command, command.properties.contains(.write), let response, response.properties.contains(.notify) else {
            finish(.failure(MotorolaFirmwareError.invalid("Motorola-Lesedienst ist nicht kompatibel."))); return
        }
        peripheral.setNotifyValue(true, for: response)
    }
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error { finish(.failure(error)); return }
        guard characteristic.isNotifying else { finish(.failure(MotorolaFirmwareError.invalid("Motorola-Antwortkanal konnte nicht geöffnet werden."))); return }
        send(4)
    }
    private func send(_ step: UInt8) {
        guard pending != nil, let peripheral, let command else { return }
        self.step = step
        do { peripheral.writeValue(try MotorolaReadProtocol.request(step), for: command, type: .withResponse) }
        catch { finish(.failure(error)) }
    }
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error { finish(.failure(error)) }
    }
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard pending != nil, characteristic.uuid == CBUUID(string: MotorolaReadProtocol.response) else { return }
        if let error { finish(.failure(error)); return }
        guard let packet = characteristic.value, packet.count >= 2, Array(packet.prefix(2)) == [0, step] else { return }
        do {
            let payload = try MotorolaReadProtocol.payload(packet, expected: step)
            switch step {
            case 4:
                modelID = try MotorolaReadProtocol.model(payload)
                guard modelID == target?.fastPairModelID, MotorolaTagModel.identify(modelID) == target?.model else {
                    throw MotorolaFirmwareError.invalid("Der verbundene Tag stimmt nicht mit dem ausgewählten Motorola-Modell überein.")
                }
                send(5)
            case 5:
                (firmware, hardware) = try MotorolaReadProtocol.hardware(payload); send(6)
            case 6:
                let battery = try MotorolaReadProtocol.battery(payload)
                finish(.success(MotorolaHardwareInfo(modelID: modelID, firmware: firmware, hardware: hardware, battery: battery)))
            default: break
            }
        } catch { finish(.failure(error)) }
    }
    private func finish(_ result: Result<MotorolaHardwareInfo, Error>) {
        guard let continuation = pending else { return }
        pending = nil; timeout?.cancel(); timeout = nil
        peripheral?.delegate = nil
        if let peripheral { central?.cancelPeripheralConnection(peripheral) }
        central?.delegate = nil; central = nil; peripheral = nil; target = nil
        continuation.resume(with: result)
    }
}
