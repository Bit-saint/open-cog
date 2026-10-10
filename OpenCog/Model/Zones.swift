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

    /// Five heart-rate zones from max heart rate.
    static func heartRate(_ bpm: Int, max: Int) -> TrainingZone? {
        guard max > 0, bpm > 0 else { return nil }
        let pct = Double(bpm) / Double(max)
        switch pct {
        case ..<0.60: return TrainingZone(number: 1, name: "Easy", color: .gray)
        case ..<0.70: return TrainingZone(number: 2, name: "Aerobic", color: .blue)
        case ..<0.80: return TrainingZone(number: 3, name: "Tempo", color: .green)
        case ..<0.90: return TrainingZone(number: 4, name: "Threshold", color: .orange)
        default: return TrainingZone(number: 5, name: "Maximum", color: .red)
        }
    }
}
