import SwiftUI

/// Bars for each step: width = duration, height = intensity, colour = power zone.
/// `progress` (0…1) dims what's done and draws a marker at the current position.
struct WorkoutProfileView: View {
    var workout: Workout
    var progress: Double?

    var body: some View {
        GeometryReader { geo in
            let total = max(Double(workout.duration), 1)
            let maxIntensity = max(workout.steps.map(\.intensity).max() ?? 1, 1.0)
            ZStack(alignment: .bottomLeading) {
                HStack(alignment: .bottom, spacing: 0) {
                    ForEach(workout.steps) { step in
                        Rectangle()
                            .fill(step.color.gradient)
                            .frame(width: max(geo.size.width * Double(step.duration) / total, 0.5),
                                   height: max(geo.size.height * step.intensity / maxIntensity, 2))
                    }
                }
                if let progress {
                    Rectangle()
                        .fill(Color(.systemBackground).opacity(0.55))
                        .frame(width: geo.size.width * progress)
                    Rectangle()
                        .fill(Color.primary)
                        .frame(width: 2)
                        .offset(x: geo.size.width * progress - 1)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .bottomLeading)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .accessibilityHidden(true)
    }
}

/// Pick a built-in workout. Starting one switches to ERG and starts the ride.
struct WorkoutPickerView: View {
    @Environment(RideEngine.self) private var engine
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(WorkoutCategory.allCases) { category in
                    Section {
                        ForEach(WorkoutLibrary.workouts(in: category)) { workout in
                            Button {
                                engine.startWorkout(workout)
                                dismiss()
                            } label: {
                                WorkoutRow(workout: workout)
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        Text(category.rawValue)
                    } footer: {
                        Text(footer(for: category))
                    }
                }
            }
            .navigationTitle("Workouts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private func footer(for category: WorkoutCategory) -> String {
        let zones = settings.heartRateZones
        switch category {
        case .vo2max:
            return "Power targets use your FTP (\(settings.ftp) W). Aim to reach heart-rate Zone 5 (≥ \(zones.lowerLimit(ofZone: 5)) bpm) in the work intervals. If an interval is too hard or easy, use the shifters (±5 W) — the change carries through the workout."
        case .zone2:
            return "Keeps your heart rate in Zone 2 (\(zones.lowerLimit(ofZone: 2))–\(zones.upperLimit(ofZone: 2) - 1) bpm) by adjusting power every 10 s. Needs your heart rate from the watch or a strap. Change zones in Settings › Heart-rate zones."
        }
    }
}

private struct WorkoutRow: View {
    var workout: Workout

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(workout.name).font(.headline)
                Spacer()
                Text(Format.duration(workout.duration))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            WorkoutProfileView(workout: workout, progress: nil)
                .frame(height: 34)
            Text(workout.summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

/// Live workout status for the ride screen: current step, countdown, next step, profile and
/// the number that matters for the goal (Zone 5 time for VO₂max, time in Zone 2 for fat burning).
struct WorkoutProgressCard: View {
    @Environment(RideEngine.self) private var engine
    @Environment(AppSettings.self) private var settings

    var body: some View {
        let controller = engine.workout
        GeometryReader { geo in
            let compact = geo.size.height < 170
            VStack(alignment: .leading, spacing: compact ? 4 : 8) {
                if let workout = controller.workout {
                    header(workout, controller: controller)
                    if controller.finished {
                        Label("Workout complete — finish the ride to save it.", systemImage: "checkmark.seal.fill")
                            .font(.headline)
                            .foregroundStyle(.green)
                        Spacer(minLength: 0)
                    } else if let step = controller.step {
                        stepRow(step, controller: controller, compact: compact)
                        Spacer(minLength: 0)
                    }
                    WorkoutProfileView(workout: workout, progress: controller.progress)
                        .frame(height: max(min(geo.size.height * 0.28, 60), 18))
                    footerRow(workout, controller: controller)
                }
            }
            .padding(12)
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .background(Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    private func header(_ workout: Workout, controller: WorkoutController) -> some View {
        HStack {
            Label(workout.name, systemImage: workout.isHeartRateControlled ? "heart.circle.fill" : "flame.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(workout.isHeartRateControlled ? .blue : .orange)
            Spacer()
            if !controller.finished {
                Button("Skip") { engine.skipWorkoutStep() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            Button("End", role: .destructive) { engine.endWorkout() }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
    }

    private func stepRow(_ step: WorkoutStep, controller: WorkoutController, compact: Bool) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(step.label)
                    .font(compact ? .headline : .title3.weight(.semibold))
                    .lineLimit(1)
                Text(targetText(step, controller: controller))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(step.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if !compact, let next = controller.nextStep {
                    Text("Next: \(next.label) · \(Format.duration(next.duration))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Text(Format.duration(controller.stepRemaining))
                .font(.system(size: compact ? 30 : 44, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(controller.stepRemaining <= 5 ? .orange : .primary)
        }
    }

    private func targetText(_ step: WorkoutStep, controller: WorkoutController) -> String {
        let watts = controller.targetWatts(ftp: settings.ftp) ?? engine.ergTarget
        switch step.target {
        case .power(let fraction):
            let adjust = controller.offsetWatts
            let offset = adjust == 0 ? "" : " (\(adjust > 0 ? "+" : "")\(adjust))"
            return "\(watts) W · \(Int((fraction * 100).rounded())) % FTP\(offset)"
        case .heartRateZone(let zone):
            let zones = settings.heartRateZones
            let band = "\(zones.lowerLimit(ofZone: zone))–\(zones.upperLimit(ofZone: zone) - 1) bpm"
            return controller.missingHeartRate ? "No heart rate — holding \(watts) W" : "Zone \(zone) \(band) · now \(watts) W"
        }
    }

    private func footerRow(_ workout: Workout, controller: WorkoutController) -> some View {
        HStack {
            Text("\(Format.duration(controller.remaining)) left")
            Spacer()
            if workout.isHeartRateControlled {
                let seconds = controller.heartRateStepSeconds
                let pct = seconds > 0 ? Int(Double(controller.secondsInHeartRateTarget) / Double(seconds) * 100) : 0
                Text("In Zone 2: \(Format.duration(controller.secondsInHeartRateTarget)) (\(pct) %)")
            } else {
                Text("Zone 5: \(Format.duration(controller.secondsInZone5))")
            }
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.secondary)
        .monospacedDigit()
    }
}
