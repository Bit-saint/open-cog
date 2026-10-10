import Foundation

/// Zwift's 24 virtual gears (chainring ÷ cog of the simulated drivetrain).
enum GearTable {
    static let ratios: [Double] = [
        0.75, 0.87, 0.99, 1.11, 1.23, 1.38, 1.53, 1.68,
        1.86, 2.04, 2.22, 2.40, 2.61, 2.82, 3.03, 3.24,
        3.49, 3.74, 3.99, 4.24, 4.54, 4.84, 5.14, 5.49,
    ]

    static var count: Int { ratios.count }
    static let range = 1...24
    /// Gear 12 (2.40 ≈ 34×14) is a comfortable starting gear.
    static let defaultGear = 12

    static func ratio(forGear gear: Int) -> Double {
        ratios[min(max(gear, range.lowerBound), range.upperBound) - 1]
    }
}
