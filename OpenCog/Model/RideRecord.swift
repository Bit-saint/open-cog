import Foundation
import SwiftData

/// A finished ride, stored with SwiftData.
@Model
final class RideRecord {
    var date: Date
    var duration: Int
    var distance: Double
    var averagePower: Int
    var normalizedPower: Int
    var maxPower: Int
    var averageHeartRate: Int?
    var maxHeartRate: Int?
    var averageCadence: Int
    var kilojoules: Int
    var tss: Double
    var ftp: Int
    @Attribute(.externalStorage) var samplesData: Data

    init(date: Date, duration: Int, distance: Double, averagePower: Int, normalizedPower: Int,
         maxPower: Int, averageHeartRate: Int?, maxHeartRate: Int?, averageCadence: Int,
         kilojoules: Int, tss: Double, ftp: Int, samples: [RideSample]) {
        self.date = date
        self.duration = duration
        self.distance = distance
        self.averagePower = averagePower
        self.normalizedPower = normalizedPower
        self.maxPower = maxPower
        self.averageHeartRate = averageHeartRate
        self.maxHeartRate = maxHeartRate
        self.averageCadence = averageCadence
        self.kilojoules = kilojoules
        self.tss = tss
        self.ftp = ftp
        self.samplesData = (try? JSONEncoder().encode(samples)) ?? Data()
    }

    var samples: [RideSample] {
        (try? JSONDecoder().decode([RideSample].self, from: samplesData)) ?? []
    }
}

extension RideRecord {
    convenience init(startDate: Date, metrics: RideMetrics, samples: [RideSample], ftp: Int) {
        self.init(date: startDate,
                  duration: metrics.seconds,
                  distance: metrics.distance,
                  averagePower: metrics.averagePower,
                  normalizedPower: metrics.normalizedPower,
                  maxPower: metrics.maxPower,
                  averageHeartRate: metrics.averageHeartRate,
                  maxHeartRate: metrics.maxHeartRate > 0 ? metrics.maxHeartRate : nil,
                  averageCadence: metrics.averageCadence,
                  kilojoules: metrics.kilojoules,
                  tss: metrics.trainingStressScore(ftp: ftp),
                  ftp: ftp,
                  samples: samples)
    }
}
