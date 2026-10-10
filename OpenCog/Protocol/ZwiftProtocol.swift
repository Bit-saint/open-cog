import Foundation

/// Zwift BLE message builders and parsers for the Van Rysel D100 (Zwift Cog) and Zwift Click v2.
/// Every message is `opcode (1 byte) + protobuf payload`, except the ASCII `RideOn` handshake.
enum Zwift {
    static let rideOn = Data("RideOn".utf8)

    enum Opcode {
        static let ridingData: UInt8 = 0x03
        static let hubCommand: UInt8 = 0x04
        static let battery: UInt8 = 0x19
        static let buttons: UInt8 = 0x23
        static let deviceInfo: UInt8 = 0x2A
        static let log: UInt8 = 0xFF
    }

    /// Zwift-standard road constants sent with every Simulation command.
    static let defaultCwA = 0.51
    static let defaultCrr = 0.004

    // MARK: HubCommand (opcode 0x04)

    /// ERG mode: the trainer holds `watts` regardless of cadence. `04 18 <watts>`
    static func ergCommand(watts: Int) -> Data {
        Data([Opcode.hubCommand] + Protobuf.field(3, UInt64(max(0, watts))))
    }

    /// SIM mode road parameters. `04 22 <len> [08 wind] 10 grade 18 cwa 20 crr`
    static func simulationCommand(gradePercent: Double,
                                  windMps: Double = 0,
                                  cwa: Double = defaultCwA,
                                  crr: Double = defaultCrr) -> Data {
        var body: [UInt8] = []
        if windMps != 0 {
            body += Protobuf.field(1, Protobuf.zigzag(Int64((windMps * 100).rounded())))
        }
        body += Protobuf.field(2, Protobuf.zigzag(Int64((gradePercent * 100).rounded())))
        body += Protobuf.field(3, UInt64((cwa * 10_000).rounded()))
        body += Protobuf.field(4, UInt64((crr * 100_000).rounded()))
        return Data([Opcode.hubCommand] + Protobuf.message(4, body))
    }

    /// Virtual gear + masses. `04 2A <len> 10 ratio 20 bikeMass 28 riderMass`
    static func physicalCommand(gearRatio: Double, bikeKg: Double, riderKg: Double) -> Data {
        let body = Protobuf.field(2, UInt64((gearRatio * 10_000).rounded()))
            + Protobuf.field(4, UInt64((bikeKg * 100).rounded()))
            + Protobuf.field(5, UInt64((riderKg * 100).rounded()))
        return Data([Opcode.hubCommand] + Protobuf.message(5, body))
    }

    static func isRideOnReply(_ data: Data) -> Bool {
        data.count >= rideOn.count && data.prefix(rideOn.count) == rideOn
    }
}

/// Trainer RidingData (opcode 0x03, ~1 Hz).
struct RidingData: Equatable {
    /// Watts (field 1).
    var power: Int
    /// Physical flywheel speed in m/s (field 3 / 100). Not the virtual road speed.
    var flywheelSpeed: Double

    init(power: Int, flywheelSpeed: Double) {
        self.power = power
        self.flywheelSpeed = flywheelSpeed
    }

    init?(_ data: Data) {
        let bytes = [UInt8](data)
        guard bytes.first == Zwift.Opcode.ridingData else { return nil }
        let fields = Protobuf.varintFields(bytes, from: 1)
        power = Int(clamping: fields[1] ?? fields[4] ?? 0)
        flywheelSpeed = Double(fields[3] ?? 0) / 100
    }
}

/// Messages sent by a Zwift Click v2 half on the Async characteristic.
enum ClickMessage: Equatable {
    /// Active-low 32-bit button bitmap (bit = 0 means pressed).
    case buttons(UInt32)
    case battery(Int)
    case other(opcode: UInt8)

    init?(_ data: Data) {
        let bytes = [UInt8](data)
        guard let opcode = bytes.first else { return nil }
        switch opcode {
        case Zwift.Opcode.buttons:
            let fields = Protobuf.varintFields(bytes, from: 1)
            // A missing field means every bit is 0, i.e. every button pressed; treat it as idle instead.
            self = .buttons(UInt32(truncatingIfNeeded: fields[1] ?? 0xFFFF_FFFF))
        case Zwift.Opcode.battery:
            let fields = Protobuf.varintFields(bytes, from: 1)
            self = .battery(Int(clamping: fields[2] ?? 0))
        default:
            self = .other(opcode: opcode)
        }
    }
}
