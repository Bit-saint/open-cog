import Foundation

enum Format {
    static func duration(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }

    /// Speed value and unit label from m/s.
    static func speed(_ mps: Double, units: UnitSystem) -> (value: String, unit: String) {
        switch units {
        case .metric: return (String(format: "%.1f", mps * 3.6), "km/h")
        case .imperial: return (String(format: "%.1f", mps * 2.236_936), "mph")
        }
    }

    /// Distance value and unit label from metres.
    static func distance(_ metres: Double, units: UnitSystem) -> (value: String, unit: String) {
        switch units {
        case .metric: return (String(format: "%.2f", metres / 1000), "km")
        case .imperial: return (String(format: "%.2f", metres / 1609.344), "mi")
        }
    }

    static func grade(_ percent: Double) -> String {
        abs(percent) < 0.05 ? "0.0%" : String(format: "%+.1f%%", percent)
    }
}
