import CoreBluetooth
import Foundation
import Observation
import os

/// BLE central for the Van Rysel D100 trainer, both Zwift Click v2 halves and a heart-rate
/// broadcaster (e.g. a Garmin watch with "Broadcast Heart Rate" enabled).
///
/// All CoreBluetooth callbacks run on the main queue.
@Observable
final class BluetoothManager: NSObject {
    private(set) var managerState: CBManagerState = .unknown
    private(set) var isScanning = false
    private(set) var links: [DeviceRole: DeviceLink] = [:]
    private(set) var discovered: [UUID: DiscoveredDevice] = [:]

    // MARK: Event callbacks

    @ObservationIgnored var onRidingData: ((RidingData) -> Void)?
    @ObservationIgnored var onButtons: (([ZwiftButton]) -> Void)?
    @ObservationIgnored var onHeartRate: ((Int?) -> Void)?
    /// Called after every successful trainer handshake (including reconnects) so the
    /// current mode, grade and gear can be pushed again.
    @ObservationIgnored var onTrainerReady: (() -> Void)?

    var holdToRepeat: Bool {
        get { clickInput.holdToRepeat }
        set { clickInput.holdToRepeat = newValue }
    }

    // MARK: Private state

    @ObservationIgnored private var central: CBCentralManager!
    @ObservationIgnored private var peripherals: [UUID: CBPeripheral] = [:]
    @ObservationIgnored private var roles: [UUID: DeviceRole] = [:]
    @ObservationIgnored private var rxCharacteristics: [UUID: CBCharacteristic] = [:]
    @ObservationIgnored private var notifying: [UUID: Set<CBUUID>] = [:]
    @ObservationIgnored private var handshakeAttempts: [UUID: Int] = [:]
    @ObservationIgnored private var pendingTrainerWrites: [Data] = []
    /// Devices the user forgot this session; never auto-connected again until picked manually.
    @ObservationIgnored private var forgotten: Set<UUID> = []
    @ObservationIgnored private var clickInput = ClickInputProcessor()
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let log = Logger(subsystem: "OpenCog", category: "Bluetooth")

    private static let restoreIdentifier = "OpenCog.central"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        super.init()
        central = CBCentralManager(delegate: self, queue: nil, options: [
            CBCentralManagerOptionRestoreIdentifierKey: Self.restoreIdentifier,
            CBCentralManagerOptionShowPowerAlertKey: true,
        ])
    }

    // MARK: Public API

    var isPoweredOn: Bool { managerState == .poweredOn }

    func link(for role: DeviceRole) -> DeviceLink? { links[role] }

    func isReady(_ role: DeviceRole) -> Bool { links[role]?.state == .ready }

    var connectedClickSides: Set<ClickSide> {
        Set(DeviceRole.allCases.compactMap { role in
            guard let side = role.clickSide, links[role]?.state == .ready else { return nil }
            return side
        })
    }

    func startScanning() {
        guard isPoweredOn, !central.isScanning else { return }
        central.scanForPeripherals(withServices: nil,
                                   options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        isScanning = true
    }

    func stopScanning() {
        guard central.isScanning else { return }
        central.stopScan()
        isScanning = false
    }

    /// Connects a discovered device to its role, replacing any device already in that role.
    func connect(deviceID: UUID) {
        guard let device = discovered[deviceID], let peripheral = peripherals[deviceID] else { return }
        connect(peripheral, as: device.role)
    }

    /// Disconnects the device in `role` and stops reconnecting to it.
    func forget(_ role: DeviceRole) {
        guard let link = links[role] else {
            setSavedID(nil, for: role)
            return
        }
        links[role] = nil
        setSavedID(nil, for: role)
        forgotten.insert(link.id)
        if let peripheral = peripherals[link.id] {
            central.cancelPeripheralConnection(peripheral)
        }
        if role == .heartRate { onHeartRate?(nil) }
    }

    /// Writes a HubCommand to the trainer, coalescing commands of the same kind
    /// while the link is busy.
    func sendToTrainer(_ command: Data) {
        guard isReady(.trainer) else { return }
        let kind = command.count > 1 ? command[command.startIndex + 1] : 0
        pendingTrainerWrites.removeAll { $0.count > 1 && $0[$0.startIndex + 1] == kind }
        pendingTrainerWrites.append(command)
        flushTrainerWrites()
    }

    // MARK: Private helpers

    private func connect(_ peripheral: CBPeripheral, as role: DeviceRole) {
        let id = peripheral.identifier
        forgotten.remove(id)
        if let existing = links[role], existing.id != id, let old = peripherals[existing.id] {
            links[role] = nil
            central.cancelPeripheralConnection(old)
        }
        peripherals[id] = peripheral
        roles[id] = role
        peripheral.delegate = self
        links[role] = DeviceLink(id: id, name: displayName(peripheral, fallback: role.title),
                                 state: .connecting, battery: nil)
        setSavedID(id, for: role)
        if peripheral.state == .connected {
            setUp(peripheral, role: role)
        } else {
            central.connect(peripheral, options: nil)
        }
    }

    private func setUp(_ peripheral: CBPeripheral, role: DeviceRole) {
        notifying[peripheral.identifier] = []
        rxCharacteristics[peripheral.identifier] = nil
        handshakeAttempts[peripheral.identifier] = 0
        updateLink(role) { $0.state = role.usesZwiftProtocol ? .handshaking : .connecting }
        peripheral.discoverServices(role.servicesToDiscover)
    }

    private func reconnectSavedDevices() {
        for role in DeviceRole.allCases {
            guard let id = savedID(for: role), links[role]?.state != .ready else { continue }
            if let known = peripherals[id] {
                connect(known, as: role)
            } else if let peripheral = central.retrievePeripherals(withIdentifiers: [id]).first {
                connect(peripheral, as: role)
            }
        }
    }

    private func classify(_ peripheral: CBPeripheral, advertisement: [String: Any]) -> DeviceRole? {
        if let data = advertisement[CBAdvertisementDataManufacturerDataKey] as? Data {
            let bytes = [UInt8](data)
            if bytes.count >= 3, Array(bytes[0..<2]) == GATT.zwiftCompanyID,
               let side = ClickSide(deviceType: bytes[2]) {
                return side == .left ? .clickLeft : .clickRight
            }
        }
        let name = (advertisement[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name ?? ""
        if name.uppercased().hasPrefix(GATT.trainerNamePrefix) { return .trainer }
        let services = advertisement[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        if services.contains(GATT.zwiftTrainerService) { return .trainer }
        if services.contains(GATT.heartRateService) { return .heartRate }
        return savedRole(for: peripheral.identifier)
    }

    private func displayName(_ peripheral: CBPeripheral, fallback: String) -> String {
        if let name = peripheral.name, !name.isEmpty { return name }
        return discovered[peripheral.identifier]?.name ?? fallback
    }

    private func updateLink(_ role: DeviceRole, _ change: (inout DeviceLink) -> Void) {
        guard var link = links[role] else { return }
        change(&link)
        if link != links[role] { links[role] = link }
    }

    private func assignedRole(of peripheral: CBPeripheral) -> DeviceRole? {
        guard let role = roles[peripheral.identifier], links[role]?.id == peripheral.identifier else { return nil }
        return role
    }

    private func sendHandshake(_ peripheral: CBPeripheral, role: DeviceRole) {
        let id = peripheral.identifier
        guard let rx = rxCharacteristics[id] else { return }
        let attempt = (handshakeAttempts[id] ?? 0) + 1
        handshakeAttempts[id] = attempt
        log.debug("RideOn → \(role.rawValue, privacy: .public) (attempt \(attempt))")
        peripheral.writeValue(Zwift.rideOn, for: rx, type: .withoutResponse)

        // No reply? Try again a few times.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, self.links[role]?.id == id, self.links[role]?.state == .handshaking,
                  peripheral.state == .connected, attempt < 4 else { return }
            self.sendHandshake(peripheral, role: role)
        }
    }

    private func markReady(_ role: DeviceRole) {
        guard let link = links[role], link.state != .ready else { return }
        updateLink(role) { $0.state = .ready }
        log.info("\(role.rawValue, privacy: .public) ready")
        if role == .trainer {
            pendingTrainerWrites.removeAll()
            onTrainerReady?()
        }
    }

    private func flushTrainerWrites() {
        guard let link = links[.trainer], let peripheral = peripherals[link.id],
              let rx = rxCharacteristics[link.id] else { return }
        while !pendingTrainerWrites.isEmpty && peripheral.canSendWriteWithoutResponse {
            peripheral.writeValue(pendingTrainerWrites.removeFirst(), for: rx, type: .withoutResponse)
        }
    }

    // MARK: Remembered devices

    private func savedKey(_ role: DeviceRole) -> String { "bluetooth.device.\(role.rawValue)" }

    func savedID(for role: DeviceRole) -> UUID? {
        defaults.string(forKey: savedKey(role)).flatMap(UUID.init(uuidString:))
    }

    private func setSavedID(_ id: UUID?, for role: DeviceRole) {
        defaults.set(id?.uuidString, forKey: savedKey(role))
    }

    private func savedRole(for id: UUID) -> DeviceRole? {
        DeviceRole.allCases.first { savedID(for: $0) == id }
    }
}

// MARK: - CBCentralManagerDelegate

extension BluetoothManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        managerState = central.state
        switch central.state {
        case .poweredOn:
            reconnectSavedDevices()
            startScanning()
        default:
            isScanning = false
            for role in links.keys {
                updateLink(role) { $0.state = .disconnected }
            }
            rxCharacteristics.removeAll()
            notifying.removeAll()
            pendingTrainerWrites.removeAll()
        }
    }

    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        let restored = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] ?? []
        for peripheral in restored {
            guard let role = savedRole(for: peripheral.identifier) else { continue }
            peripherals[peripheral.identifier] = peripheral
            roles[peripheral.identifier] = role
            peripheral.delegate = self
            links[role] = DeviceLink(id: peripheral.identifier,
                                     name: displayName(peripheral, fallback: role.title),
                                     state: .connecting, battery: nil)
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard let role = classify(peripheral, advertisement: advertisementData) else { return }
        let id = peripheral.identifier
        let now = Date()
        if let existing = discovered[id], now.timeIntervalSince(existing.lastSeen) < 1 { return }

        let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
            ?? peripheral.name ?? role.title
        discovered[id] = DiscoveredDevice(id: id, name: name, role: role, rssi: RSSI.intValue, lastSeen: now)
        if peripherals[id] == nil { peripherals[id] = peripheral }

        // Auto-connect: trainer and Clicks connect to the remembered device, or the first
        // one found. Heart-rate monitors only reconnect to a remembered device, because
        // many may be nearby; the user picks one in the Devices tab.
        guard links[role] == nil, !forgotten.contains(id) else { return }
        let saved = savedID(for: role)
        switch role {
        case .trainer, .clickLeft, .clickRight:
            if saved == nil || saved == id { connect(peripheral, as: role) }
        case .heartRate:
            if saved == id { connect(peripheral, as: role) }
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard let role = assignedRole(of: peripheral) else {
            central.cancelPeripheralConnection(peripheral)
            return
        }
        log.info("Connected \(role.rawValue, privacy: .public)")
        updateLink(role) { $0.name = self.displayName(peripheral, fallback: role.title) }
        setUp(peripheral, role: role)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral,
                        error: Error?) {
        guard let role = assignedRole(of: peripheral) else { return }
        log.error("Failed to connect \(role.rawValue, privacy: .public): \(error?.localizedDescription ?? "-", privacy: .public)")
        updateLink(role) { $0.state = .connecting }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, self.assignedRole(of: peripheral) == role, self.isPoweredOn else { return }
            self.central.connect(peripheral, options: nil)
        }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {
        let id = peripheral.identifier
        rxCharacteristics[id] = nil
        notifying[id] = nil
        guard let role = assignedRole(of: peripheral) else {
            roles[id] = nil
            return
        }
        log.info("Disconnected \(role.rawValue, privacy: .public)")
        if let side = role.clickSide { clickInput.reset(side: side) }
        if role == .heartRate { onHeartRate?(nil) }
        if role == .trainer { pendingTrainerWrites.removeAll() }

        // Keep a pending connection open: iOS reconnects as soon as the device advertises again
        // (a Click wakes on a button press).
        updateLink(role) { $0.state = .connecting }
        if isPoweredOn { central.connect(peripheral, options: nil) }
    }
}

// MARK: - CBPeripheralDelegate

extension BluetoothManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        for service in peripheral.services ?? [] {
            switch service.uuid {
            case GATT.zwiftTrainerService, GATT.zwiftClickService:
                peripheral.discoverCharacteristics([GATT.zwiftAsync, GATT.zwiftSyncRx, GATT.zwiftSyncTx],
                                                   for: service)
            case GATT.heartRateService:
                peripheral.discoverCharacteristics([GATT.heartRateMeasurement], for: service)
            case GATT.batteryService:
                peripheral.discoverCharacteristics([GATT.batteryLevel], for: service)
            default:
                break
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        for characteristic in service.characteristics ?? [] {
            switch characteristic.uuid {
            case GATT.zwiftAsync, GATT.zwiftSyncTx, GATT.heartRateMeasurement:
                peripheral.setNotifyValue(true, for: characteristic)
            case GATT.zwiftSyncRx:
                rxCharacteristics[peripheral.identifier] = characteristic
                handshakeIfPossible(peripheral)
            case GATT.batteryLevel:
                if characteristic.properties.contains(.read) { peripheral.readValue(for: characteristic) }
                if characteristic.properties.contains(.notify) { peripheral.setNotifyValue(true, for: characteristic) }
            default:
                break
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic,
                    error: Error?) {
        if let error {
            log.error("Notify \(characteristic.uuid.uuidString, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        guard characteristic.isNotifying, let role = assignedRole(of: peripheral) else { return }
        notifying[peripheral.identifier, default: []].insert(characteristic.uuid)
        if characteristic.uuid == GATT.heartRateMeasurement {
            markReady(role)
        } else {
            handshakeIfPossible(peripheral)
        }
    }

    /// Notifications must be enabled on Async and Sync TX before `RideOn` is written.
    private func handshakeIfPossible(_ peripheral: CBPeripheral) {
        let id = peripheral.identifier
        guard let role = assignedRole(of: peripheral), role.usesZwiftProtocol,
              links[role]?.state == .handshaking, handshakeAttempts[id, default: 0] == 0,
              rxCharacteristics[id] != nil,
              let enabled = notifying[id], enabled.contains(GATT.zwiftAsync), enabled.contains(GATT.zwiftSyncTx)
        else { return }
        sendHandshake(peripheral, role: role)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        guard error == nil, let data = characteristic.value, let role = assignedRole(of: peripheral) else { return }

        switch characteristic.uuid {
        case GATT.zwiftSyncTx:
            if Zwift.isRideOnReply(data) { markReady(role) }

        case GATT.zwiftAsync:
            // Events only flow after a successful handshake.
            markReady(role)
            if role == .trainer {
                if let riding = RidingData(data) { onRidingData?(riding) }
            } else if let side = role.clickSide, let message = ClickMessage(data) {
                switch message {
                case .buttons(let bitmap):
                    let presses = clickInput.process(bitmap: bitmap, from: side,
                                                     connected: connectedClickSides,
                                                     now: ProcessInfo.processInfo.systemUptime)
                    if !presses.isEmpty { onButtons?(presses) }
                case .battery(let percent):
                    updateLink(role) { $0.battery = percent }
                case .other:
                    break
                }
            }

        case GATT.heartRateMeasurement:
            if let measurement = HeartRateMeasurement(data) {
                onHeartRate?(measurement.bpm > 0 ? measurement.bpm : nil)
            }

        case GATT.batteryLevel:
            if let percent = data.first { updateLink(role) { $0.battery = Int(percent) } }

        default:
            break
        }
    }

    func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        if assignedRole(of: peripheral) == .trainer { flushTrainerWrites() }
    }
}
