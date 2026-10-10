import SwiftUI

/// Mode switch plus gear and grade (Gears mode) or target power (ERG mode), sized to fit a
/// fixed slot on the ride screen: `.vertical` for the landscape sidebar, `.horizontal` for the
/// strip at the bottom in portrait.
struct TrainerPanel: View {
    enum Layout { case vertical, horizontal }
    var layout: Layout

    @Environment(RideEngine.self) private var engine
    @Environment(BluetoothManager.self) private var bluetooth

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            VStack(spacing: layout == .vertical ? min(14, h * 0.03) : 8) {
                Picker("Mode", selection: Binding(get: { engine.mode }, set: { engine.setMode($0) })) {
                    ForEach(TrainerMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                if engine.mode == .sim {
                    if layout == .vertical {
                        Spacer(minLength: 0)
                        gearBlock(numberSize: min(72, h * 0.16))
                        GearIndicator(gear: engine.gear)
                        Spacer(minLength: 0)
                        Divider()
                        Spacer(minLength: 0)
                        gradeBlock(numberSize: min(36, h * 0.08))
                        Spacer(minLength: 0)
                    } else {
                        HStack(spacing: 12) {
                            gearBlock(numberSize: min(56, h * 0.36))
                                .frame(maxWidth: .infinity)
                            Divider()
                            gradeBlock(numberSize: min(34, h * 0.22))
                                .frame(maxWidth: .infinity)
                        }
                        .frame(maxHeight: .infinity)
                    }
                } else {
                    Spacer(minLength: 0)
                    ergBlock(numberSize: layout == .vertical ? min(64, h * 0.14) : min(52, h * 0.34))
                    Spacer(minLength: 0)
                }

                if !bluetooth.isReady(.trainer) {
                    Label("Trainer not connected", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .padding(14)
            .frame(width: geo.size.width, height: geo.size.height)
            .background(Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .animation(.snappy, value: engine.mode)
    }

    // MARK: Blocks

    private func gearBlock(numberSize: CGFloat) -> some View {
        HStack {
            RoundControlButton(systemImage: "minus", accessibilityLabel: "Shift to easier gear",
                               size: buttonSize(numberSize)) {
                engine.shiftDown()
            }
            .disabled(engine.gear <= GearTable.range.lowerBound)
            Spacer(minLength: 4)
            VStack(spacing: 0) {
                Text("GEAR")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("\(engine.gear)")
                    .font(.system(size: numberSize, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(engine.gear)))
                    .animation(.snappy, value: engine.gear)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text(String(format: "%.2f", GearTable.ratio(forGear: engine.gear)))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Gear \(engine.gear) of \(GearTable.count)")
            Spacer(minLength: 4)
            RoundControlButton(systemImage: "plus", accessibilityLabel: "Shift to harder gear",
                               size: buttonSize(numberSize)) {
                engine.shiftUp()
            }
            .disabled(engine.gear >= GearTable.range.upperBound)
        }
    }

    private func gradeBlock(numberSize: CGFloat) -> some View {
        let buttons = HStack(spacing: 10) {
            RoundControlButton(systemImage: "arrow.down.right", accessibilityLabel: "Decrease grade",
                               size: buttonSize(numberSize) * 0.85) {
                engine.adjustGrade(by: -RideEngine.gradeStep)
            }
            RoundControlButton(systemImage: "arrow.up.right", accessibilityLabel: "Increase grade",
                               size: buttonSize(numberSize) * 0.85) {
                engine.adjustGrade(by: RideEngine.gradeStep)
            }
        }
        let value = VStack(alignment: layout == .vertical ? .leading : .center, spacing: 0) {
            Text("GRADE")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(Format.grade(engine.grade))
                .font(.system(size: numberSize, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText(value: engine.grade))
                .animation(.snappy, value: engine.grade)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .accessibilityElement(children: .combine)

        return Group {
            if layout == .vertical {
                HStack {
                    value
                    Spacer(minLength: 4)
                    buttons
                }
            } else {
                VStack(spacing: 6) {
                    value
                    buttons
                }
            }
        }
    }

    private func ergBlock(numberSize: CGFloat) -> some View {
        VStack(spacing: 8) {
            HStack {
                RoundControlButton(systemImage: "minus", accessibilityLabel: "Decrease target by 5 watts",
                                   size: buttonSize(numberSize)) {
                    engine.adjustErgTarget(by: -5)
                }
                Spacer(minLength: 4)
                VStack(spacing: 0) {
                    Text(engine.workout.isActive ? "WORKOUT TARGET" : "TARGET")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text("\(engine.ergTarget)")
                            .font(.system(size: numberSize, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(.numericText(value: Double(engine.ergTarget)))
                            .animation(.snappy, value: engine.ergTarget)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                        Text("W")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
                Spacer(minLength: 4)
                RoundControlButton(systemImage: "plus", accessibilityLabel: "Increase target by 5 watts",
                                   size: buttonSize(numberSize)) {
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
                    .controlSize(.small)
                    .accessibilityLabel("\(step > 0 ? "Increase" : "Decrease") target by \(abs(step)) watts")
                }
            }
        }
    }

    private func buttonSize(_ numberSize: CGFloat) -> CGFloat {
        min(max(numberSize * 0.85, 40), 60)
    }
}

/// 24 small bars; the current gear and everything easier are filled.
struct GearIndicator: View {
    var gear: Int

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(GearTable.range, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(index <= gear ? Color.accentColor : Color(.tertiarySystemFill))
                    .frame(height: 6 + CGFloat(index) * 0.6)
            }
        }
        .frame(height: 21, alignment: .bottom)
        .animation(.snappy, value: gear)
        .accessibilityHidden(true)
    }
}
