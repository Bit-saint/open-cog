import Foundation

/// One recorded second of a ride.
struct RideSample: Codable, Equatable {
    /// Seconds of moving time since the ride started.
    var t: Int
    var power: Int
    var heartRate: Int?
    var cadence: Int
    /// Virtual speed, m/s.
    var speed: Double
    var gear: Int
    var grade: Double
    var ergTarget: Int?
}

/// Running ride statistics, updated once per recorded second.
struct RideMetrics: Equatable {
    private(set) var seconds = 0
    private(set) var distance = 0.0 // m
    private(set) var energyJoules = 0.0
    private(set) var maxPower = 0
    private(set) var maxHeartRate = 0
    private(set) var maxSpeed = 0.0

    private var powerSum = 0
    private var cadenceSum = 0
    private var cadenceCount = 0
    private var heartRateSum = 0
    private var heartRateCount = 0

    // Normalized Power: rolling 30 s average, then 4th-power mean.
    private var window: [Int] = []
    private var windowSum = 0
    private var fourthPowerSum = 0.0
    private var fourthPowerCount = 0

    mutating func add(_ sample: RideSample) {
        seconds += 1
        distance += sample.speed
        energyJoules += Double(sample.power)
        powerSum += sample.power
        maxPower = max(maxPower, sample.power)
        maxSpeed = max(maxSpeed, sample.speed)
        if sample.cadence > 0 {
            cadenceSum += sample.cadence
            cadenceCount += 1
        }
        if let hr = sample.heartRate, hr > 0 {
            heartRateSum += hr
            heartRateCount += 1
            maxHeartRate = max(maxHeartRate, hr)
        }

        window.append(sample.power)
        windowSum += sample.power
        if window.count > 30 {
            windowSum -= window.removeFirst()
        }
        if window.count == 30 {
            let rolling = Double(windowSum) / 30
            fourthPowerSum += pow(rolling, 4)
            fourthPowerCount += 1
        }
    }

    var averagePower: Int { seconds > 0 ? powerSum / seconds : 0 }
    var averageCadence: Int { cadenceCount > 0 ? cadenceSum / cadenceCount : 0 }
    var averageHeartRate: Int? { heartRateCount > 0 ? heartRateSum / heartRateCount : nil }
    var kilojoules: Int { Int(energyJoules / 1000) }
    var averageSpeed: Double { seconds > 0 ? distance / Double(seconds) : 0 }

    var normalizedPower: Int {
        if fourthPowerCount > 0 {
            return Int(pow(fourthPowerSum / Double(fourthPowerCount), 0.25).rounded())
        }
        return averagePower
    }

    func trainingStressScore(ftp: Int) -> Double {
        guard ftp > 0, seconds > 0 else { return 0 }
        let np = Double(normalizedPower)
        return Double(seconds) * np * np / (Double(ftp * ftp) * 3600) * 100
    }

    func intensityFactor(ftp: Int) -> Double {
        guard ftp > 0 else { return 0 }
        return Double(normalizedPower) / Double(ftp)
    }
}
