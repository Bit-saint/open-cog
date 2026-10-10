import Foundation

/// FTMS Indoor Bike Data (0x2AD2). Fields appear in flag order; only the ones up to
/// instantaneous power are decoded. The D100 sends speed + power.
struct IndoorBikeData: Equatable {
    var speedKmh: Double?
    var cadence: Double?
    var power: Int?

    init(speedKmh: Double?, cadence: Double?, power: Int?) {
        self.speedKmh = speedKmh
        self.cadence = cadence
        self.power = power
    }

    init?(_ data: Data) {
        guard let parsed = Self.parse([UInt8](data)) else { return nil }
        self = parsed
    }

    private static func parse(_ b: [UInt8]) -> IndoorBikeData? {
        guard b.count >= 2 else { return nil }
        let flags = Int(b[0]) | Int(b[1]) << 8
        var i = 2
        var speed: Double?
        var cadence: Double?
        var power: Int?

        func u16() -> Int? {
            guard i + 2 <= b.count else { return nil }
            defer { i += 2 }
            return Int(b[i]) | Int(b[i + 1]) << 8
        }

        if flags & 0x01 == 0 { // "More Data" clear → instantaneous speed present
            guard let v = u16() else { return nil }
            speed = Double(v) / 100
        }
        if flags & 0x02 != 0 { guard u16() != nil else { return nil } } // average speed
        if flags & 0x04 != 0 {
            guard let v = u16() else { return nil }
            cadence = Double(v) / 2
        }
        if flags & 0x08 != 0 { guard u16() != nil else { return nil } } // average cadence
        if flags & 0x10 != 0 { // total distance, uint24
            guard i + 3 <= b.count else { return nil }
            i += 3
        }
        if flags & 0x20 != 0 { guard u16() != nil else { return nil } } // resistance level
        if flags & 0x40 != 0 {
            guard let v = u16() else { return nil }
            power = Int(Int16(truncatingIfNeeded: v))
        }
        return IndoorBikeData(speedKmh: speed, cadence: cadence, power: power)
    }
}

/// Cycling Power Measurement (0x2A63): flags (uint16) then instantaneous power (sint16).
struct CyclingPowerMeasurement: Equatable {
    var power: Int

    init?(_ data: Data) {
        let b = [UInt8](data)
        guard b.count >= 4 else { return nil }
        power = Int(Int16(truncatingIfNeeded: Int(b[2]) | Int(b[3]) << 8))
    }
}
