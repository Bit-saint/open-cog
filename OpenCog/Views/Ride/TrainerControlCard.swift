import SwiftUI

/// Mode switch plus gear/grade (Gears mode) or target power (ERG mode).
struct TrainerControlCard: View {
    @Environment(RideEngine.self) private var engine
    @Environment(BluetoothManager.self) private var bluetooth

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Picker("Mode", selection: Binding(get: { engine.mode }, set: { engine.setMode($0) })) {
                ForEach(TrainerMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            if engine.mode == .sim {
                GearControl()
                Divider()
                GradeControl()
            } else {
                ErgControl()
            }

            if !bluetooth.isReady(.trainer) {
                Label("Trainer not connected", systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
        .card()
        .animation(.snappy, value: engine.mode)
    }
}

private struct GearControl: View {
    @Environment(RideEngine.self) private var engine

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                RoundControlButton(systemImage: "minus", accessibilityLabel: "Shift to easier gear", size: 64) {
                    engine.shiftDown()
                }
                .disabled(engine.gear <= GearTable.range.lowerBound)

                Spacer()

                VStack(spacing: 0) {
                    Text("GEAR")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("\(engine.gear)")
                        .font(.system(size: 72, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(engine.gear)))
                        .animation(.snappy, value: engine.gear)
                    Text(String(format: "Ratio %.2f", GearTable.ratio(forGear: engine.gear)))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Gear \(engine.gear) of \(GearTable.count)")

                Spacer()

                RoundControlButton(systemImage: "plus", accessibilityLabel: "Shift to harder gear", size: 64) {
                    engine.shiftUp()
                }
                .disabled(engine.gear >= GearTable.range.upperBound)
            }

            GearIndicator(gear: engine.gear)
        }
    }
}

/// 24 small bars; the current gear and everything easier are filled.
private struct GearIndicator: View {
    var gear: Int

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(GearTable.range, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(index <= gear ? Color.accentColor : Color(.tertiarySystemFill))
                    .frame(height: 8 + CGFloat(index) * 0.75)
            }
        }
        .frame(height: 26, alignment: .bottom)
        .animation(.snappy, value: gear)
        .accessibilityHidden(true)
    }
}

private struct GradeControl: View {
    @Environment(RideEngine.self) private var engine

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Grade")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(Format.grade(engine.grade))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: engine.grade))
                        .animation(.snappy, value: engine.grade)
                }
                Spacer()
                RoundControlButton(systemImage: "arrow.down.right", accessibilityLabel: "Decrease grade", size: 48) {
                    engine.adjustGrade(by: -RideEngine.gradeStep)
                }
                RoundControlButton(systemImage: "arrow.up.right", accessibilityLabel: "Increase grade", size: 48) {
                    engine.adjustGrade(by: RideEngine.gradeStep)
                }
            }
            if engine.grade < 0 {
                Text("The trainer rides descents as flat; the extra speed is shown on screen.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct ErgControl: View {
    @Environment(RideEngine.self) private var engine

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                RoundControlButton(systemImage: "minus", accessibilityLabel: "Decrease target by 5 watts", size: 64) {
                    engine.adjustErgTarget(by: -5)
                }
                Spacer()
                VStack(spacing: 0) {
                    Text("TARGET")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(engine.ergTarget)")
                            .font(.system(size: 64, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(.numericText(value: Double(engine.ergTarget)))
                            .animation(.snappy, value: engine.ergTarget)
                        Text("W")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
                Spacer()
                RoundControlButton(systemImage: "plus", accessibilityLabel: "Increase target by 5 watts", size: 64) {
                    engine.adjustErgTarget(by: 5)
                }
            }

            HStack {
                ForEach([-25, -10, 10, 25], id: \.self) { step in
                    Button { engine.adjustErgTarget(by: step) } label: {
                        Text(step > 0 ? "+\(step)" : "\(step)")
                            .monospacedDigit()
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("\(step > 0 ? "Increase" : "Decrease") target by \(abs(step)) watts")
                }
            }

            Text("Shifters adjust the target by 5 W in ERG mode.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
