import Foundation
import Observation

enum UnitSystem: String, CaseIterable, Identifiable {
    case metric, imperial
    var id: String { rawValue }
    var title: String { self == .metric ? "Metric" : "Imperial" }
}

/// User settings persisted in UserDefaults.
@Observable
final class AppSettings {
    private let defaults: UserDefaults

    var riderWeightKg: Double { didSet { defaults.set(riderWeightKg, forKey: Keys.riderWeight) } }
    var bikeWeightKg: Double { didSet { defaults.set(bikeWeightKg, forKey: Keys.bikeWeight) } }
    var chainringTeeth: Int { didSet { defaults.set(chainringTeeth, forKey: Keys.chainring) } }
    var cogTeeth: Int { didSet { defaults.set(cogTeeth, forKey: Keys.cog) } }
    var wheelCircumferenceMm: Int { didSet { defaults.set(wheelCircumferenceMm, forKey: Keys.wheel) } }
    var ftp: Int { didSet { defaults.set(ftp, forKey: Keys.ftp) } }
    var maxHeartRate: Int { didSet { defaults.set(maxHeartRate, forKey: Keys.maxHR) } }
    var restingHeartRate: Int { didSet { defaults.set(restingHeartRate, forKey: Keys.restingHR) } }
    var heartRateZoneMethod: HeartRateZoneMethod {
        didSet { defaults.set(heartRateZoneMethod.rawValue, forKey: Keys.zoneMethod) }
    }
    /// Where heart-rate zones 2–5 start (fractions of max HR or HR reserve).
    var heartRateZoneBoundaries: [Double] {
        didSet { defaults.set(heartRateZoneBoundaries, forKey: Keys.zoneBoundaries) }
    }
    var startingGear: Int { didSet { defaults.set(startingGear, forKey: Keys.startingGear) } }
    var holdToRepeat: Bool { didSet { defaults.set(holdToRepeat, forKey: Keys.holdToRepeat) } }
    var autoPause: Bool { didSet { defaults.set(autoPause, forKey: Keys.autoPause) } }
    var units: UnitSystem { didSet { defaults.set(units.rawValue, forKey: Keys.units) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Keys.riderWeight: 75.0,
            Keys.bikeWeight: 10.0,
            Keys.chainring: 34,
            Keys.cog: 14,
            Keys.wheel: 2096,
            Keys.ftp: 200,
            Keys.maxHR: 185,
            Keys.restingHR: 60,
            Keys.zoneMethod: HeartRateZoneMethod.percentOfMax.rawValue,
            Keys.startingGear: GearTable.defaultGear,
            Keys.holdToRepeat: true,
            Keys.autoPause: true,
            Keys.units: UnitSystem.metric.rawValue,
        ])
        riderWeightKg = defaults.double(forKey: Keys.riderWeight)
        bikeWeightKg = defaults.double(forKey: Keys.bikeWeight)
        chainringTeeth = defaults.integer(forKey: Keys.chainring)
        cogTeeth = defaults.integer(forKey: Keys.cog)
        wheelCircumferenceMm = defaults.integer(forKey: Keys.wheel)
        ftp = defaults.integer(forKey: Keys.ftp)
        maxHeartRate = defaults.integer(forKey: Keys.maxHR)
        restingHeartRate = defaults.integer(forKey: Keys.restingHR)
        heartRateZoneMethod = HeartRateZoneMethod(rawValue: defaults.string(forKey: Keys.zoneMethod) ?? "") ?? .percentOfMax
        let storedBoundaries = defaults.array(forKey: Keys.zoneBoundaries) as? [Double] ?? []
        heartRateZoneBoundaries = storedBoundaries.count == 4 ? storedBoundaries : HeartRateZones.defaultBoundaries
        startingGear = defaults.integer(forKey: Keys.startingGear)
        holdToRepeat = defaults.bool(forKey: Keys.holdToRepeat)
        autoPause = defaults.bool(forKey: Keys.autoPause)
        units = UnitSystem(rawValue: defaults.string(forKey: Keys.units) ?? "") ?? .metric
    }

    var totalMassKg: Double { riderWeightKg + bikeWeightKg }

    var heartRateZones: HeartRateZones {
        HeartRateZones(method: heartRateZoneMethod, maxHeartRate: maxHeartRate,
                       restingHeartRate: restingHeartRate, boundaries: heartRateZoneBoundaries)
    }

    private enum Keys {
        static let riderWeight = "settings.riderWeightKg"
        static let bikeWeight = "settings.bikeWeightKg"
        static let chainring = "settings.chainringTeeth"
        static let cog = "settings.cogTeeth"
        static let wheel = "settings.wheelCircumferenceMm"
        static let ftp = "settings.ftp"
        static let maxHR = "settings.maxHeartRate"
        static let restingHR = "settings.restingHeartRate"
        static let zoneMethod = "settings.heartRateZoneMethod"
        static let zoneBoundaries = "settings.heartRateZoneBoundaries"
        static let startingGear = "settings.startingGear"
        static let holdToRepeat = "settings.holdToRepeat"
        static let autoPause = "settings.autoPause"
        static let units = "settings.units"
    }
}
