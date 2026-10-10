import SwiftUI

/// What the trainer should do during a workout step.
enum WorkoutTarget: Equatable {
    /// ERG at a fraction of FTP (1.0 = FTP).
    case power(Double)
    /// ERG watts adjusted continuously to keep heart rate inside this heart-rate zone (1–5),
    /// using the zone limits from Settings.
    case heartRateZone(Int)
}

struct WorkoutStep: Equatable, Identifiable {
    let id = UUID()
    var label: String
    var duration: Int // seconds
    var target: WorkoutTarget

    /// Relative intensity for the profile chart and colours (fraction of FTP).
    var intensity: Double {
        switch target {
        case .power(let fraction): return fraction
        case .heartRateZone: return 0.65 // Zone 2 ≈ 56–75 % FTP
        }
    }

    var isHeartRateControlled: Bool {
        if case .heartRateZone = target { return true }
        return false
    }

    /// Colour by power zone.
    var color: Color {
        if isHeartRateControlled { return .blue }
        switch intensity {
        case ..<0.56: return .gray
        case ..<0.76: return .blue
        case ..<0.91: return .green
        case ..<1.06: return .yellow
        case ..<1.21: return .orange
        default: return .red
        }
    }

    static func == (lhs: WorkoutStep, rhs: WorkoutStep) -> Bool {
        lhs.label == rhs.label && lhs.duration == rhs.duration && lhs.target == rhs.target
    }
}

enum WorkoutCategory: String, CaseIterable, Identifiable {
    case vo2max = "VO₂max Intervals"
    case zone2 = "Zone 2 · Fat Burning"
    var id: String { rawValue }
}

struct Workout: Identifiable, Equatable {
    var id: String
    var name: String
    var category: WorkoutCategory
    var summary: String
    var steps: [WorkoutStep]

    var duration: Int { steps.reduce(0) { $0 + $1.duration } }
    var isHeartRateControlled: Bool { steps.contains { $0.isHeartRateControlled } }
}

/// Built-in workouts. Power targets are fractions of FTP; heart-rate targets fractions of max HR.
enum WorkoutLibrary {
    static let all: [Workout] = [norwegian4x4, ronnestad3015, fiveByThree, zone2(minutes: 45), zone2(minutes: 60), zone2(minutes: 90)]

    static func workouts(in category: WorkoutCategory) -> [Workout] {
        all.filter { $0.category == category }
    }

    private static func warmUp() -> [WorkoutStep] {
        [WorkoutStep(label: "Warm-up", duration: 300, target: .power(0.50)),
         WorkoutStep(label: "Warm-up", duration: 180, target: .power(0.65)),
         WorkoutStep(label: "Warm-up", duration: 120, target: .power(0.75))]
    }

    private static func coolDown(_ seconds: Int = 300) -> WorkoutStep {
        WorkoutStep(label: "Cool-down", duration: seconds, target: .power(0.45))
    }

    /// Repeats `work`/`rest` `count` times, dropping the final rest (the cool-down follows).
    private static func repeats(_ count: Int, work: WorkoutStep, rest: WorkoutStep) -> [WorkoutStep] {
        var steps: [WorkoutStep] = []
        for index in 1...count {
            var w = work
            w.label = "\(work.label) \(index)/\(count)"
            steps.append(w)
            if index < count { steps.append(rest) }
        }
        return steps
    }

    static let norwegian4x4 = Workout(
        id: "norwegian-4x4",
        name: "Norwegian 4×4",
        category: .vo2max,
        summary: "4 × 4 min at 110 % FTP (aim for heart-rate Zone 5) with 3 min easy between. The classic VO₂max session.",
        steps: warmUp()
            + repeats(4, work: WorkoutStep(label: "Interval", duration: 240, target: .power(1.10)),
                      rest: WorkoutStep(label: "Recover", duration: 180, target: .power(0.50)))
            + [coolDown()]
    )

    static let ronnestad3015: Workout = {
        var steps = warmUp()
        for set in 1...3 {
            for rep in 1...13 {
                steps.append(WorkoutStep(label: "Set \(set) · \(rep)/13 hard", duration: 30, target: .power(1.25)))
                steps.append(WorkoutStep(label: "Set \(set) · \(rep)/13 easy", duration: 15, target: .power(0.50)))
            }
            if set < 3 { steps.append(WorkoutStep(label: "Recover", duration: 180, target: .power(0.45))) }
        }
        steps.append(coolDown())
        return Workout(
            id: "ronnestad-30-15",
            name: "Rønnestad 30/15",
            category: .vo2max,
            summary: "3 sets of 13 × (30 s hard / 15 s easy), 3 min between sets. Keeps you near VO₂max longer than steady intervals.",
            steps: steps
        )
    }()

    static let fiveByThree = Workout(
        id: "5x3",
        name: "5 × 3 min",
        category: .vo2max,
        summary: "5 × 3 min at 115 % FTP with 3 min easy between. A shorter VO₂max session to start with.",
        steps: warmUp()
            + repeats(5, work: WorkoutStep(label: "Interval", duration: 180, target: .power(1.15)),
                      rest: WorkoutStep(label: "Recover", duration: 180, target: .power(0.50)))
            + [coolDown()]
    )

    static func zone2(minutes: Int) -> Workout {
        Workout(
            id: "zone2-\(minutes)",
            name: "Zone 2 · \(minutes) min",
            category: .zone2,
            summary: "Heart-rate controlled: the trainer adjusts power to keep you in your heart-rate Zone 2. Builds fat-burning capacity.",
            steps: [WorkoutStep(label: "Warm-up", duration: 300, target: .power(0.50)),
                    WorkoutStep(label: "Zone 2", duration: minutes * 60, target: .heartRateZone(2)),
                    coolDown()]
        )
    }
}
