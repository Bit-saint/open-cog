import SwiftUI

/// Training zones used to tint the live power and heart-rate tiles.
struct TrainingZone: Equatable {
    var number: Int
    var name: String
    var color: Color

    /// Coggan power zones from FTP.
    static func power(_ watts: Int, ftp: Int) -> TrainingZone? {
        guard ftp > 0, watts > 0 else { return nil }
        let pct = Double(watts) / Double(ftp)
        switch pct {
        case ..<0.55: return TrainingZone(number: 1, name: "Recovery", color: .gray)
        case ..<0.75: return TrainingZone(number: 2, name: "Endurance", color: .blue)
        case ..<0.90: return TrainingZone(number: 3, name: "Tempo", color: .green)
        case ..<1.05: return TrainingZone(number: 4, name: "Threshold", color: .yellow)
        case ..<1.20: return TrainingZone(number: 5, name: "VO₂ Max", color: .orange)
        case ..<1.50: return TrainingZone(number: 6, name: "Anaerobic", color: .red)
        default: return TrainingZone(number: 7, name: "Neuromuscular", color: .purple)
        }
    }

    /// Colours of heart-rate zones 1–5.
    static let heartRateColors: [Color] = [.gray, .blue, .green, .orange, .red]
    static let heartRateNames = ["Easy", "Aerobic", "Tempo", "Threshold", "Maximum"]
}

enum HeartRateZoneMethod: String, CaseIterable, Identifiable {
    /// Limits are percentages of max heart rate (Garmin's default).
    case percentOfMax
    /// Limits are percentages of heart-rate reserve (max − resting), the Karvonen method.
    case heartRateReserve

    var id: String { rawValue }
    var title: String { self == .percentOfMax ? "% Max HR" : "% HR Reserve" }
}

/// The rider's five heart-rate zones, configured in Settings.
struct HeartRateZones: Equatable {
    var method: HeartRateZoneMethod
    var maxHeartRate: Int
    var restingHeartRate: Int
    /// Where zones 2, 3, 4 and 5 start, as fractions of max HR or of HR reserve. Ascending.
    var boundaries: [Double]

    /// Same as Garmin's default %-of-max zones: Z2 60 %, Z3 70 %, Z4 80 %, Z5 90 %.
    static let defaultBoundaries = [0.60, 0.70, 0.80, 0.90]

    /// Heart rate at a fraction of max HR or of HR reserve.
    func bpm(at fraction: Double) -> Int {
        switch method {
        case .percentOfMax:
            return Int((fraction * Double(maxHeartRate)).rounded())
        case .heartRateReserve:
            let reserve = Double(maxHeartRate - restingHeartRate)
            return Int((Double(restingHeartRate) + fraction * reserve).rounded())
        }
    }

    /// Lowest heart rate of zones 2…5.
    var limits: [Int] { boundaries.prefix(4).map(bpm(at:)) }

    /// Lowest heart rate in `zone` (1–5). Zone 1 starts at 0.
    func lowerLimit(ofZone zone: Int) -> Int {
        guard zone > 1 else { return 0 }
        let index = min(zone, 5) - 2
        return index < limits.count ? limits[index] : maxHeartRate
    }

    /// Heart rate where `zone` ends (the next zone's start); max HR for zone 5.
    func upperLimit(ofZone zone: Int) -> Int {
        let index = zone - 1
        return zone < 5 && index >= 0 && index < limits.count ? limits[index] : maxHeartRate
    }

    func zone(for bpm: Int) -> TrainingZone? {
        guard bpm > 0, maxHeartRate > 0 else { return nil }
        let number = 1 + limits.filter { bpm >= $0 }.count
        return TrainingZone(number: number, name: TrainingZone.heartRateNames[number - 1],
                            color: TrainingZone.heartRateColors[number - 1])
    }
}
