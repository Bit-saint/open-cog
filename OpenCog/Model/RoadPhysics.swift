import Foundation

/// Virtual-road physics. The trainer reports physical flywheel speed, so the on-screen speed
/// is derived from power, grade and mass (docs/BLUETOOTH_PROTOCOL.md §6).
enum RoadPhysics {
    static let gravity = 9.81
    /// Sea-level air density, kg/m³.
    static let airDensity = 1.225

    /// Steady-state power needed to ride at `speed` m/s.
    /// `cwa` is Zwift's "cw·A" — drag coefficient × frontal area in m² (cw is the German symbol
    /// for Cd), so aerodynamic power is ½·ρ·CwA·v³.
    static func power(atSpeed speed: Double, gradePercent: Double, totalMassKg: Double,
                      cwa: Double = Zwift.defaultCwA, crr: Double = Zwift.defaultCrr) -> Double {
        let theta = atan(gradePercent / 100)
        let rolling = totalMassKg * gravity * (sin(theta) + crr * cos(theta))
        return speed * rolling + 0.5 * airDensity * cwa * speed * speed * speed
    }

    /// Solves `power(atSpeed:) == watts` for speed by bisection over 0…30 m/s.
    /// Negative grades are honoured here even though the trainer ignores them,
    /// so descents still feel fast on screen.
    static func speed(forPower watts: Double, gradePercent: Double, totalMassKg: Double,
                      cwa: Double = Zwift.defaultCwA, crr: Double = Zwift.defaultCrr) -> Double {
        let watts = max(0, watts)
        let f: (Double) -> Double = {
            power(atSpeed: $0, gradePercent: gradePercent, totalMassKg: totalMassKg, cwa: cwa, crr: crr) - watts
        }
        var low = 0.0
        var high = 30.0
        if f(high) <= 0 { return high }
        // On a descent f dips below zero before rising; start from the minimum so the
        // bracket always contains the positive root.
        if watts == 0 && gradePercent >= 0 { return 0 }
        for _ in 0..<60 {
            let mid = (low + high) / 2
            if f(mid) > 0 { high = mid } else { low = mid }
        }
        return (low + high) / 2
    }

    /// Virtual road speed with virtual shifting. The flywheel turns as if the bike were in the
    /// physical gear (chainring ÷ Zwift Cog); the trainer simulates the virtual gear, so the road
    /// speed it is simulating is the flywheel speed scaled by virtual ÷ physical ratio
    /// (= cadence × virtual ratio × wheel circumference).
    static func virtualSpeed(flywheelSpeed: Double, gearRatio: Double, chainringTeeth: Int, cogTeeth: Int) -> Double {
        guard chainringTeeth > 0, cogTeeth > 0 else { return flywheelSpeed }
        return flywheelSpeed * gearRatio / (Double(chainringTeeth) / Double(cogTeeth))
    }

    /// Cadence estimate from flywheel speed. The Zwift Cog fixes the physical gear,
    /// so cadence is proportional to flywheel speed.
    static func cadence(flywheelSpeed: Double, chainringTeeth: Int, cogTeeth: Int,
                        wheelCircumferenceMm: Int) -> Double {
        guard chainringTeeth > 0, cogTeeth > 0, wheelCircumferenceMm > 0 else { return 0 }
        let metresPerCrankRev = Double(chainringTeeth) / Double(cogTeeth) * Double(wheelCircumferenceMm) / 1000
        return flywheelSpeed / metresPerCrankRev * 60
    }
}
