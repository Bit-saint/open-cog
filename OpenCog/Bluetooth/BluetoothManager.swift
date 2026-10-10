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
    /// Most recent Bluetooth events, newest last (Devices › Diagnostics).
    private(set) var eventLog: [BLELogEntry] = []
    private(set) var stats: [DeviceRole: LinkStats] = [:]

    // MARK: Event callbacks

    @ObservationIgnored var onRidingData: ((RidingData) -> Void)?
    /// Power/speed from FTMS or Cycling Power, used when Zwift RidingData isn't arriving.
    @ObservationIgnored var onTrainerFallbackData: ((TrainerFallbackData) -> Void)?
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
    @ObservationIgnored private var lastClickBitmap: [DeviceRole: UInt32] = [:]
    @ObservationIgnored private var lastLoggedCommand: [UInt8: Data] = [:]
    @ObservationIgnored private var loggedFallbackSources: Set<String> = []
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
        stats[role] = LinkStats()
        lastClickBitmap[role] = nil
        if role == .trainer {
            lastLoggedCommand.removeAll()
            loggedFallbackSources.removeAll()
        }
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
        let name = (advertisement[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name ?? ""
        // Check the trainer name first so Zwift manufacturer data on the trainer can't make it look like a Click.
        if name.uppercased().hasPrefix(GATT.trainerNamePrefix) { return .trainer }
        if let data = advertisement[CBAdvertisementDataManufacturerDataKey] as? Data {
            let bytes = [UInt8](data)
            if bytes.count >= 3, Array(bytes[0..<2]) == GATT.zwiftCompanyID,
               let side = ClickSide(deviceType: bytes[2]) {
                return side == .left ? .clickLeft : .clickRight
            }
        }
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
        updateStats(role) { $0.handshakeAttempts = attempt }
        record(role, "→ RideOn (attempt \(attempt), \(writeType(for: rx) == .withResponse ? "with" : "without") response)")
        peripheral.writeValue(Zwift.rideOn, for: rx, type: writeType(for: rx))

        // The reference implementation (trainer_core.py) never waits for the trainer's reply:
        // it writes RideOn, waits 0.5 s and starts sending commands. Do the same.
        if role == .trainer && attempt == 1 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self, self.links[role]?.id == id, self.links[role]?.state == .handshaking,
                      peripheral.state == .connected else { return }
                self.record(role, "Starting without waiting for the RideOn reply")
                self.markReady(role)
            }
        }

        // No reply? Try again; after several attempts carry on anyway so commands still go out.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, self.links[role]?.id == id, self.links[role]?.state == .handshaking,
                  peripheral.state == .connected else { return }
            if attempt < 5 {
                self.sendHandshake(peripheral, role: role)
            } else {
                self.record(role, "No RideOn reply after \(attempt) attempts; continuing without it")
                self.markReady(role)
            }
        }
    }

    /// Sync RX is write-without-response on the devices tested; fall back to a normal write otherwise.
    private func writeType(for characteristic: CBCharacteristic) -> CBCharacteristicWriteType {
        characteristic.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
    }

    private func markReady(_ role: DeviceRole) {
        guard let link = links[role], link.state != .ready else { return }
        updateLink(role) { $0.state = .ready }
        record(role, "Ready")
        if role == .trainer {
            pendingTrainerWrites.removeAll()
            onTrainerReady?()
        }
    }

    private func flushTrainerWrites() {
        guard let link = links[.trainer], let peripheral = peripherals[link.id],
              let rx = rxCharacteristics[link.id] else { return }
        while !pendingTrainerWrites.isEmpty && peripheral.canSendWriteWithoutResponse {
            let command = pendingTrainerWrites.removeFirst()
            peripheral.writeValue(command, for: rx, type: writeType(for: rx))
            let kind = command.count > 1 ? command[command.startIndex + 1] : 0
            updateStats(.trainer) {
                $0.commandsWritten += 1
                $0.lastCommand = command.hexString
            }
            if lastLoggedCommand[kind] != command {
                lastLoggedCommand[kind] = command
                record(.trainer, "→ \(Self.describe(command)): \(command.hexString)")
            }
        }
    }

    // MARK: Diagnostics

    private func record(_ role: DeviceRole?, _ text: String) {
        log.info("[\(role?.rawValue ?? "-", privacy: .public)] \(text, privacy: .public)")
        eventLog.append(BLELogEntry(date: Date(), role: role, text: text))
        if eventLog.count > 400 { eventLog.removeFirst(eventLog.count - 400) }
    }

    private func updateStats(_ role: DeviceRole, _ change: (inout LinkStats) -> Void) {
        var value = stats[role] ?? LinkStats()
        change(&value)
        stats[role] = value
    }

    func clearLog() { eventLog.removeAll() }

    /// Plain-text report for sharing.
    func diagnosticsReport() -> String {
        let time = DateFormatter()
        time.dateFormat = "HH:mm:ss.SSS"
        var lines = ["OpenCog Bluetooth diagnostics — \(Date().formatted())", "Bluetooth state: \(managerState.rawValue)", ""]
        for role in DeviceRole.allCases {
            guard let link = links[role] else {
                lines.append("\(role.title): not paired")
                continue
            }
            let s = stats[role] ?? LinkStats()
            lines.append("\(role.title): \(link.name) — \(link.state.title)")
            lines.append("  services: \(s.services.joined(separator: ", "))")
            lines.append("  notifying: \(s.notifying.joined(separator: ", "))")
            lines.append("  handshake attempts: \(s.handshakeAttempts), confirmed: \(s.handshakeConfirmed)")
            lines.append("  packets: \(s.packetsReceived), last: \(s.lastPacket ?? "-")")
            if role == .trainer {
                lines.append("  commands: \(s.commandsWritten), last: \(s.lastCommand ?? "-")")
            }
        }
        lines.append("")
        lines.append("Events:")
        for entry in eventLog {
            lines.append("\(time.string(from: entry.date)) [\(entry.role?.rawValue ?? "-")] \(entry.text)")
        }
        return lines.joined(separator: "\n")
    }

    static func describe(_ properties: CBCharacteristicProperties) -> String {
        var names: [String] = []
        if properties.contains(.read) { names.append("read") }
        if properties.contains(.write) { names.append("write") }
        if properties.contains(.writeWithoutResponse) { names.append("write-no-resp") }
        if properties.contains(.notify) { names.append("notify") }
        if properties.contains(.indicate) { names.append("indicate") }
        return names.joined(separator: ",")
    }

    static func describe(_ command: Data) -> String {
        guard command.count > 1 else { return "command" }
        switch command[command.startIndex + 1] {
        case 0x18: return "ERG"
        case 0x22: return "Simulation"
        case 0x2A: return "Gear"
        default: return "Command"
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
        record(role, "Connected to \(displayName(peripheral, fallback: role.title))")
        updateLink(role) { $0.name = self.displayName(peripheral, fallback: role.title) }
        setUp(peripheral, role: role)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral,
                        error: Error?) {
        guard let role = assignedRole(of: peripheral) else { return }
        record(role, "Failed to connect: \(error?.localizedDescription ?? "unknown error")")
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
        record(role, "Disconnected\(error.map { ": \($0.localizedDescription)" } ?? "")")
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
        if let role = assignedRole(of: peripheral) {
            let names = (peripheral.services ?? []).map(\.uuid.label)
            updateStats(role) { $0.services = names }
            record(role, "Services: \(names.isEmpty ? "none" : names.joined(separator: ", "))\(error.map { " (error: \($0.localizedDescription))" } ?? "")")
            if role.usesZwiftProtocol, !(peripheral.services ?? []).contains(where: {
                $0.uuid == GATT.zwiftTrainerService || $0.uuid == GATT.zwiftClickService
            }) {
                record(role, "Zwift service not found on this device")
            }
        }
        for service in peripheral.services ?? [] {
            switch service.uuid {
            case GATT.zwiftTrainerService, GATT.zwiftClickService:
                peripheral.discoverCharacteristics([GATT.zwiftAsync, GATT.zwiftSyncRx, GATT.zwiftSyncTx],
                                                   for: service)
            case GATT.heartRateService:
                peripheral.discoverCharacteristics([GATT.heartRateMeasurement], for: service)
            case GATT.batteryService:
                peripheral.discoverCharacteristics([GATT.batteryLevel], for: service)
            case GATT.fitnessMachineService:
                peripheral.discoverCharacteristics([GATT.indoorBikeData], for: service)
            case GATT.cyclingPowerService:
                peripheral.discoverCharacteristics([GATT.cyclingPowerMeasurement], for: service)
            default:
                break
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        let role = assignedRole(of: peripheral)
        if let role, service.uuid == GATT.zwiftTrainerService || service.uuid == GATT.zwiftClickService {
            let chars = (service.characteristics ?? []).map { "\($0.uuid.label) [\(Self.describe($0.properties))]" }
            record(role, "Zwift characteristics: \(chars.joined(separator: ", "))\(error.map { " (error: \($0.localizedDescription))" } ?? "")")
            // If the notification callbacks never confirm, send RideOn anyway after a moment.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                guard let self, self.assignedRole(of: peripheral) == role,
                      self.links[role]?.state == .handshaking,
                      self.handshakeAttempts[peripheral.identifier, default: 0] == 0,
                      self.rxCharacteristics[peripheral.identifier] != nil else { return }
                self.record(role, "Notifications not confirmed yet; sending RideOn anyway")
                self.sendHandshake(peripheral, role: role)
            }
        }
        for characteristic in service.characteristics ?? [] {
            switch characteristic.uuid {
            case GATT.zwiftAsync, GATT.zwiftSyncTx, GATT.heartRateMeasurement,
                 GATT.indoorBikeData, GATT.cyclingPowerMeasurement:
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
            record(assignedRole(of: peripheral), "Enabling notifications on \(characteristic.uuid.label) failed: \(error.localizedDescription)")
            return
        }
        guard characteristic.isNotifying, let role = assignedRole(of: peripheral) else { return }
        notifying[peripheral.identifier, default: []].insert(characteristic.uuid)
        updateStats(role) { $0.notifying.append(characteristic.uuid.label) }
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
        guard let role = assignedRole(of: peripheral) else { return }
        if let error {
            record(role, "Read \(characteristic.uuid.label) failed: \(error.localizedDescription)")
            return
        }
        guard let data = characteristic.value else { return }

        switch characteristic.uuid {
        case GATT.zwiftSyncTx:
            record(role, "← Sync TX: \(data.hexString)")
            if Zwift.isRideOnReply(data) {
                updateStats(role) { $0.handshakeConfirmed = true }
                markReady(role)
            }

        case GATT.zwiftAsync:
            // Events only flow after a successful handshake.
            markReady(role)
            let count = (stats[role]?.packetsReceived ?? 0) + 1
            updateStats(role) {
                $0.packetsReceived = count
                $0.lastPacket = data.hexString
                $0.lastPacketDate = Date()
            }
            if role == .trainer {
                if count <= 3 || count % 30 == 0 { record(role, "← Async #\(count): \(data.hexString)") }
                if let riding = RidingData(data) {
                    onRidingData?(riding)
                } else if count <= 3 {
                    record(role, "Async packet is not RidingData")
                }
            } else if let side = role.clickSide, let message = ClickMessage(data) {
                switch message {
                case .buttons(let bitmap):
                    if lastClickBitmap[role] != bitmap {
                        if lastClickBitmap[role] != nil || bitmap != 0xFFFF_FFFF {
                            record(role, "← Buttons \(String(format: "%08X", bitmap))")
                        }
                        lastClickBitmap[role] = bitmap
                    }
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

        case GATT.indoorBikeData:
            if let bike = IndoorBikeData(data) {
                if loggedFallbackSources.insert("FTMS").inserted {
                    record(role, "← FTMS Indoor Bike Data: \(data.hexString)")
                }
                onTrainerFallbackData?(TrainerFallbackData(source: "FTMS", power: bike.power,
                                                           speedMps: bike.speedKmh.map { $0 / 3.6 },
                                                           cadence: bike.cadence))
            }

        case GATT.cyclingPowerMeasurement:
            if let measurement = CyclingPowerMeasurement(data) {
                if loggedFallbackSources.insert("CP").inserted {
                    record(role, "← Cycling Power: \(data.hexString)")
                }
                onTrainerFallbackData?(TrainerFallbackData(source: "Cycling Power", power: measurement.power,
                                                           speedMps: nil, cadence: nil))
            }

        default:
            break
        }
    }

    func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        if assignedRole(of: peripheral) == .trainer { flushTrainerWrites() }
    }
}
