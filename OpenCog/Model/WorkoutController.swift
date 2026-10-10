import Foundation
import Observation

/// Runs a structured workout: advances through steps once per recorded second, works out the
/// ERG target for each step, and for heart-rate steps adjusts watts to hold heart rate in the
/// target band. Pure logic (no Bluetooth), so it can be unit tested.
@Observable
final class WorkoutController {
    private(set) var workout: Workout?
    private(set) var stepIndex = 0
    private(set) var stepElapsed = 0
    private(set) var elapsed = 0
    private(set) var finished = false
    /// Manual ± adjustment (shifters / buttons) applied to power steps for the rest of the workout.
    private(set) var offsetWatts = 0
    /// Current watts chosen by the heart-rate controller.
    private(set) var heartRateWatts: Double = 0
    /// True while a heart-rate step has no heart-rate data (watts are held).
    private(set) var missingHeartRate = false
    /// Seconds at or above the Zone 5 lower limit (the time that drives VO₂max gains).
    private(set) var secondsInZone5 = 0
    private(set) var secondsInHeartRateTarget = 0
    private(set) var heartRateStepSeconds = 0

    /// How often the heart-rate controller adjusts power. Heart rate responds slowly to load.
    static let heartRateAdjustInterval = 10
    /// Watts per bpm of error per adjustment, and the largest single change.
    static let heartRateGain = 0.8
    static let heartRateMaxStep = 8.0

    var isActive: Bool { workout != nil && !finished }

    var step: WorkoutStep? {
        guard let workout, stepIndex < workout.steps.count else { return nil }
        return workout.steps[stepIndex]
    }

    var nextStep: WorkoutStep? {
        guard let workout, stepIndex + 1 < workout.steps.count else { return nil }
        return workout.steps[stepIndex + 1]
    }

    var stepRemaining: Int { max(0, (step?.duration ?? 0) - stepElapsed) }
    var remaining: Int { max(0, (workout?.duration ?? 0) - elapsed) }

    var progress: Double {
        guard let total = workout?.duration, total > 0 else { return 0 }
        return min(1, Double(elapsed) / Double(total))
    }

    /// Start time of the current step within the workout.
    private var stepStart: Int {
        guard let workout else { return 0 }
        return workout.steps.prefix(stepIndex).reduce(0) { $0 + $1.duration }
    }

    // MARK: Lifecycle

    func start(_ workout: Workout, ftp: Int) {
        self.workout = workout
        stepIndex = 0
        stepElapsed = 0
        elapsed = 0
        finished = false
        offsetWatts = 0
        heartRateWatts = Double(ftp) * 0.60
        missingHeartRate = false
        secondsInZone5 = 0
        secondsInHeartRateTarget = 0
        heartRateStepSeconds = 0
    }

    func end() {
        workout = nil
        finished = false
    }

    /// Skip to the next step. Returns true if there was one.
    @discardableResult
    func skip() -> Bool {
        guard let workout, isActive else { return false }
        elapsed = stepStart + (step?.duration ?? 0)
        stepElapsed = 0
        if stepIndex + 1 < workout.steps.count {
            stepIndex += 1
            return true
        }
        finished = true
        return false
    }

    /// Manual adjustment: nudges the heart-rate controller's watts on a heart-rate step,
    /// otherwise shifts all power steps by `delta`.
    func nudge(_ delta: Int) {
        guard isActive else { return }
        if step?.isHeartRateControlled == true {
            heartRateWatts += Double(delta)
        } else {
            offsetWatts += delta
        }
    }

    // MARK: Ticking

    enum Event: Equatable {
        case stepChanged
        case finished
    }

    /// Advance one recorded second.
    /// - Parameter zones: heart-rate zone limits from Settings.
    func advance(heartRate: Int?, zones: HeartRateZones, ftp: Int) -> Event? {
        guard isActive, let current = step else { return nil }

        if let heartRate, heartRate >= zones.lowerLimit(ofZone: 5) {
            secondsInZone5 += 1
        }
        if case let .heartRateZone(zone) = current.target {
            controlHeartRate(heartRate, lowBpm: Double(zones.lowerLimit(ofZone: zone)),
                             highBpm: Double(zones.upperLimit(ofZone: zone)), ftp: ftp)
        }

        stepElapsed += 1
        elapsed += 1
        guard stepElapsed >= current.duration else { return nil }

        stepElapsed = 0
        if let workout, stepIndex + 1 < workout.steps.count {
            stepIndex += 1
            return .stepChanged
        }
        finished = true
        return .finished
    }

    private func controlHeartRate(_ heartRate: Int?, lowBpm: Double, highBpm: Double, ftp: Int) {
        heartRateStepSeconds += 1
        guard let heartRate, highBpm > lowBpm else {
            missingHeartRate = true
            return
        }
        missingHeartRate = false
        if Double(heartRate) >= lowBpm && Double(heartRate) <= highBpm {
            secondsInHeartRateTarget += 1
        }
        guard stepElapsed % Self.heartRateAdjustInterval == Self.heartRateAdjustInterval - 1 else { return }

        let targetBpm = (lowBpm + highBpm) / 2
        var change = (targetBpm - Double(heartRate)) * Self.heartRateGain
        change = min(max(change, -Self.heartRateMaxStep), Self.heartRateMaxStep)
        // Well above the band: back off harder.
        if Double(heartRate) > highBpm + 5 { change = -Self.heartRateMaxStep * 1.5 }
        let ceiling = max(Double(ftp) * 0.90, 60)
        heartRateWatts = min(max(heartRateWatts + change, 50), ceiling)
    }

    /// ERG watts for the current step.
    func targetWatts(ftp: Int) -> Int? {
        guard isActive, let step else { return nil }
        let watts: Int
        switch step.target {
        case .power(let fraction):
            watts = Int((fraction * Double(ftp) / 5).rounded()) * 5 + offsetWatts
        case .heartRateZone:
            watts = Int(heartRateWatts.rounded())
        }
        return min(max(watts, RideEngine.ergRange.lowerBound), RideEngine.ergRange.upperBound)
    }

    /// Watts a step will ask for (for previews), ignoring the heart-rate controller.
    static func previewWatts(for step: WorkoutStep, ftp: Int) -> Int {
        Int((step.intensity * Double(ftp) / 5).rounded()) * 5
    }
}
