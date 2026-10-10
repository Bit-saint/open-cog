import Foundation

/// After-ride numbers for the fat-burning and VO₂max goals, computed from recorded samples.
struct RideAnalysis: Equatable {
    /// Seconds in heart-rate zones 1–5.
    var heartRateZoneSeconds: [Int]
    /// Rough estimate of fat oxidised, grams.
    var fatGrams: Double
    var carbGrams: Double
    /// Metabolic energy, kcal (mechanical work ÷ ~24 % gross efficiency).
    var kilocalories: Double
    /// Aerobic decoupling (Pw:HR drift) between first and second half, percent. nil if too short.
    var decouplingPercent: Double?

    static let grossEfficiency = 0.24

    init(samples: [RideSample], zones heartRateZones: HeartRateZones, ftp: Int) {
        var zones = [Int](repeating: 0, count: 5)
        var fatKcal = 0.0
        var carbKcal = 0.0
        for sample in samples {
            if let hr = sample.heartRate, let zone = heartRateZones.zone(for: hr) {
                zones[zone.number - 1] += 1
            }
            let kcal = Double(sample.power) / Self.grossEfficiency / 4184
            let fat = Self.fatFraction(intensity: ftp > 0 ? Double(sample.power) / Double(ftp) : 0)
            fatKcal += kcal * fat
            carbKcal += kcal * (1 - fat)
        }
        heartRateZoneSeconds = zones
        kilocalories = fatKcal + carbKcal
        fatGrams = fatKcal / 9
        carbGrams = carbKcal / 4
        decouplingPercent = Self.decoupling(samples)
    }

    /// Share of energy from fat by intensity (fraction of FTP). A simplified curve from
    /// substrate-utilisation studies: ~60 % at easy endurance pace, falling to almost none
    /// above threshold. Individual values vary a lot, so treat results as an estimate.
    static func fatFraction(intensity: Double) -> Double {
        guard intensity > 0 else { return 0 }
        if intensity <= 0.55 { return 0.60 }
        return min(max(0.60 - (intensity - 0.55) * 1.6, 0), 0.60)
    }

    /// Efficiency factor (power ÷ HR) of the first half versus the second half of the riding
    /// with heart rate. Under 5 % means a solid aerobic base. Needs at least 20 minutes.
    static func decoupling(_ samples: [RideSample]) -> Double? {
        let usable = samples.filter { ($0.heartRate ?? 0) > 0 && $0.power > 0 }
        guard usable.count >= 20 * 60 else { return nil }
        let half = usable.count / 2
        func efficiency(_ slice: ArraySlice<RideSample>) -> Double {
            let power = slice.reduce(0.0) { $0 + Double($1.power) }
            let hr = slice.reduce(0.0) { $0 + Double($1.heartRate ?? 0) }
            return hr > 0 ? power / hr : 0
        }
        let first = efficiency(usable[..<half])
        let second = efficiency(usable[half...])
        guard first > 0 else { return nil }
        return (first - second) / first * 100
    }
}
