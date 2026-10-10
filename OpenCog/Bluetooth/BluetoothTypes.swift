import CoreBluetooth
import Foundation

enum GATT {
    // Zwift service (trainer) and the Click v2 service share the same three characteristics.
    static let zwiftTrainerService = CBUUID(string: "00000001-19CA-4651-86E5-FA29DCDD09D1")
    static let zwiftClickService = CBUUID(string: "FC82")
    static let zwiftAsync = CBUUID(string: "00000002-19CA-4651-86E5-FA29DCDD09D1")
    static let zwiftSyncRx = CBUUID(string: "00000003-19CA-4651-86E5-FA29DCDD09D1")
    static let zwiftSyncTx = CBUUID(string: "00000004-19CA-4651-86E5-FA29DCDD09D1")

    static let heartRateService = CBUUID(string: "180D")
    static let heartRateMeasurement = CBUUID(string: "2A37")
    static let batteryService = CBUUID(string: "180F")
    static let batteryLevel = CBUUID(string: "2A19")

    // Standard trainer services, read only as a fallback data source (power, speed, cadence).
    static let fitnessMachineService = CBUUID(string: "1826")
    static let indoorBikeData = CBUUID(string: "2AD2")
    static let cyclingPowerService = CBUUID(string: "1818")
    static let cyclingPowerMeasurement = CBUUID(string: "2A63")

    /// Zwift Inc. Bluetooth company identifier, little-endian in manufacturer data.
    static let zwiftCompanyID: [UInt8] = [0x4A, 0x09]
    static let trainerNamePrefix = "VANRYSEL"
}

enum DeviceRole: String, CaseIterable, Identifiable, Codable {
    case trainer, clickLeft, clickRight, heartRate

    var id: String { rawValue }

    var title: String {
        switch self {
        case .trainer: return "Smart Trainer"
        case .clickLeft: return "Zwift Click (Left)"
        case .clickRight: return "Zwift Click (Right)"
        case .heartRate: return "Heart Rate"
        }
    }

    var systemImage: String {
        switch self {
        case .trainer: return "bicycle"
        case .clickLeft: return "minus.circle"
        case .clickRight: return "plus.circle"
        case .heartRate: return "heart.fill"
        }
    }

    var clickSide: ClickSide? {
        switch self {
        case .clickLeft: return .left
        case .clickRight: return .right
        default: return nil
        }
    }

    var usesZwiftProtocol: Bool { self != .heartRate }

    var servicesToDiscover: [CBUUID] {
        switch self {
        case .trainer: return [GATT.zwiftTrainerService, GATT.fitnessMachineService, GATT.cyclingPowerService]
        case .clickLeft, .clickRight: return [GATT.zwiftClickService, GATT.batteryService]
        case .heartRate: return [GATT.heartRateService, GATT.batteryService]
        }
    }
}

enum LinkState: Equatable {
    case disconnected
    case connecting
    case handshaking
    case ready

    var title: String {
        switch self {
        case .disconnected: return "Not connected"
        case .connecting: return "Connecting…"
        case .handshaking: return "Handshaking…"
        case .ready: return "Connected"
        }
    }
}

/// Live state of a device assigned to a role.
struct DeviceLink: Equatable {
    var id: UUID
    var name: String
    var state: LinkState
    var battery: Int?
}

/// A device seen while scanning.
struct DiscoveredDevice: Identifiable, Equatable {
    var id: UUID
    var name: String
    var role: DeviceRole
    var rssi: Int
    var lastSeen: Date
}

/// One line of the on-screen Bluetooth diagnostics log.
struct BLELogEntry: Identifiable, Equatable {
    let id = UUID()
    var date: Date
    var role: DeviceRole?
    var text: String
}

/// Per-device counters shown in Diagnostics.
struct LinkStats: Equatable {
    var services: [String] = []
    var notifying: [String] = []
    var handshakeAttempts = 0
    var handshakeConfirmed = false
    var packetsReceived = 0
    var lastPacket: String?
    var lastPacketDate: Date?
    var commandsWritten = 0
    var lastCommand: String?
}

/// Power/speed/cadence from the standard FTMS or Cycling Power services.
struct TrainerFallbackData: Equatable {
    var source: String
    var power: Int?
    var speedMps: Double?
    var cadence: Double?
}

extension Data {
    var hexString: String { map { String(format: "%02X", $0) }.joined(separator: " ") }
}

extension CBUUID {
    /// Short human-readable name for the UUIDs this app uses.
    var label: String {
        switch self {
        case GATT.zwiftTrainerService: return "Zwift (trainer)"
        case GATT.zwiftClickService: return "Zwift (Click)"
        case GATT.zwiftAsync: return "Async"
        case GATT.zwiftSyncRx: return "Sync RX"
        case GATT.zwiftSyncTx: return "Sync TX"
        case GATT.heartRateService: return "Heart Rate"
        case GATT.heartRateMeasurement: return "HR Measurement"
        case GATT.batteryService: return "Battery"
        case GATT.batteryLevel: return "Battery Level"
        case GATT.fitnessMachineService: return "FTMS"
        case GATT.indoorBikeData: return "Indoor Bike Data"
        case GATT.cyclingPowerService: return "Cycling Power"
        case GATT.cyclingPowerMeasurement: return "CP Measurement"
        default: return uuidString
        }
    }
}
