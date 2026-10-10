import SwiftData
import SwiftUI

struct RideView: View {
    @Binding var selectedTab: AppTab

    @Environment(RideEngine.self) private var engine
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.modelContext) private var modelContext

    @State private var confirmingFinish = false
    @State private var finishedRide: RideRecord?
    @State private var visibleFeedback: ControlFeedback?

    var body: some View {
        NavigationStack {
            Group {
                if horizontalSizeClass == .regular {
                    regularLayout
                } else {
                    compactLayout
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Ride")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { selectedTab = .devices } label: { DeviceStatusBar() }
                        .accessibilityHint("Opens Devices")
                }
            }
            .safeAreaInset(edge: .bottom) {
                if horizontalSizeClass != .regular {
                    RideControls(confirmingFinish: $confirmingFinish)
                        .padding(.horizontal)
                        .padding(.vertical, 10)
                        .background(.bar)
                }
            }
            .overlay(alignment: .top) { feedbackToast }
            .confirmationDialog("Finish this ride?", isPresented: $confirmingFinish, titleVisibility: .visible) {
                Button("Save Ride") { saveRide() }
                Button("Discard Ride", role: .destructive) { engine.discard() }
                Button("Keep Riding", role: .cancel) {}
            }
            .sheet(item: $finishedRide) { ride in
                NavigationStack {
                    RideDetailView(ride: ride)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { finishedRide = nil }
                            }
                        }
                }
            }
        }
        .sensoryFeedback(.selection, trigger: engine.gear)
        .sensoryFeedback(.impact(weight: .medium), trigger: engine.state)
        .onChange(of: engine.feedback) { _, feedback in
            guard let feedback else { return }
            withAnimation(.snappy) { visibleFeedback = feedback }
            Task {
                try? await Task.sleep(for: .seconds(1.2))
                if visibleFeedback?.id == feedback.id {
                    withAnimation(.easeOut) { visibleFeedback = nil }
                }
            }
        }
    }

    // MARK: Layouts

    /// iPad (and large iPhones in landscape): full-width metrics, with ride controls bottom-left
    /// and a compact gear/grade panel floating in the bottom-right corner.
    private var regularLayout: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(spacing: 20) {
                    RideHeader()
                    HeroMetrics()
                    SecondaryMetrics(columns: [GridItem(.adaptive(minimum: 170), spacing: 14)])
                    LiveChartCard()
                }
                .padding(20)
                .padding(.bottom, 290) // room to scroll past the floating panels
            }

            HStack(alignment: .bottom, spacing: 20) {
                RideControls(confirmingFinish: $confirmingFinish)
                    .padding(12)
                    .frame(maxWidth: 380)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .shadow(color: .black.opacity(0.12), radius: 14, y: 5)
                Spacer(minLength: 0)
                TrainerControlPanel()
                    .frame(width: 330)
            }
            .padding(20)
        }
    }

    private var compactLayout: some View {
        ScrollView {
            VStack(spacing: 16) {
                RideHeader()
                HeroMetrics()
                SecondaryMetrics(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)])
                TrainerControlCard()
                LiveChartCard()
            }
            .padding()
        }
    }

    @ViewBuilder
    private var feedbackToast: some View {
        if let feedback = visibleFeedback {
            Label(feedback.text, systemImage: feedback.systemImage)
                .font(.headline)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(.regularMaterial, in: Capsule())
                .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .id(feedback.id)
        }
    }

    private func saveRide() {
        guard let record = engine.finish() else { return }
        modelContext.insert(record)
        try? modelContext.save()
        finishedRide = record
    }
}

// MARK: - Header

private struct RideHeader: View {
    @Environment(RideEngine.self) private var engine

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text(stateTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(stateColor)
                Text(Format.duration(engine.metrics.seconds))
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(engine.mode == .sim ? "Gear \(engine.gear)" : "ERG \(engine.ergTarget) W")
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                if engine.mode == .sim {
                    Text("Grade \(Format.grade(engine.grade))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .card()
        .accessibilityElement(children: .combine)
    }

    private var stateTitle: String {
        switch engine.state {
        case .idle: return "Ready to ride"
        case .riding: return "Recording"
        case .paused: return "Paused"
        case .autoPaused: return "Auto-paused"
        }
    }

    private var stateColor: Color {
        switch engine.state {
        case .idle: return .secondary
        case .riding: return .green
        case .paused, .autoPaused: return .orange
        }
    }
}

// MARK: - Metrics

/// Heart rate (tinted by zone) and speed, larger than everything else.
private struct HeroMetrics: View {
    @Environment(RideEngine.self) private var engine
    @Environment(AppSettings.self) private var settings
    @Environment(BluetoothManager.self) private var bluetooth

    var body: some View {
        HStack(spacing: 14) {
            heartRate
            speed
        }
    }

    private var heartRate: some View {
        let bpm = engine.heartRate
        let zone = bpm.flatMap { TrainingZone.heartRate($0, max: settings.maxHeartRate) }
        let badge: String
        if let zone {
            badge = "Zone \(zone.number) · \(zone.name)"
        } else if bluetooth.link(for: .heartRate) == nil {
            badge = "Pair your watch in Devices"
        } else {
            badge = bluetooth.isReady(.heartRate) ? "Waiting for data…" : "Connecting…"
        }
        return HeroMetricTile(title: "Heart Rate", value: bpm.map { "\($0)" } ?? "--", unit: "bpm",
                              tint: zone?.color ?? .red, badge: badge, tinted: zone != nil) {
            Image(systemName: "heart.fill")
                .symbolEffect(.pulse, options: .repeating, isActive: bpm != nil)
        } footer: {
            HeartRateZoneBar(current: zone?.number)
        }
    }

    private var speed: some View {
        let current = Format.speed(engine.virtualSpeed, units: settings.units)
        let average = Format.speed(engine.metrics.averageSpeed, units: settings.units)
        let max = Format.speed(engine.metrics.maxSpeed, units: settings.units)
        return HeroMetricTile(title: "Speed", value: current.value, unit: current.unit, tint: .blue,
                              badge: nil, tinted: false) {
            Image(systemName: "speedometer")
        } footer: {
            Text(engine.metrics.seconds > 0 ? "Avg \(average.value) · Max \(max.value) \(current.unit)" : "Virtual road speed")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

/// Five segments for the heart-rate zones; the current one is full colour and taller.
private struct HeartRateZoneBar: View {
    var current: Int?

    var body: some View {
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(Array(TrainingZone.heartRateColors.enumerated()), id: \.offset) { index, color in
                let active = current == index + 1
                Capsule()
                    .fill(color.opacity(active ? 1 : 0.25))
                    .frame(height: active ? 10 : 6)
            }
        }
        .frame(height: 10, alignment: .bottom)
        .animation(.snappy, value: current)
        .accessibilityHidden(true)
    }
}

private struct SecondaryMetrics: View {
    var columns: [GridItem]

    @Environment(RideEngine.self) private var engine
    @Environment(AppSettings.self) private var settings

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            let powerZone = TrainingZone.power(engine.powerAverage3s, ftp: settings.ftp)
            MetricTile(title: "Power", value: "\(engine.power)", unit: "W", systemImage: "bolt.fill",
                       tint: powerZone?.color ?? .yellow,
                       detail: powerZone.map { "Z\($0.number) · \($0.name)" } ?? "3s avg \(engine.powerAverage3s) W")

            MetricTile(title: "Cadence", value: "\(engine.cadence)", unit: "rpm",
                       systemImage: "arrow.triangle.2.circlepath", tint: .teal,
                       detail: "Estimated")

            let distance = Format.distance(engine.metrics.distance, units: settings.units)
            MetricTile(title: "Distance", value: distance.value, unit: distance.unit,
                       systemImage: "point.topleft.down.to.point.bottomright.curvepath", tint: .indigo)

            MetricTile(title: "Avg Power", value: "\(engine.metrics.averagePower)", unit: "W",
                       systemImage: "chart.bar.fill", tint: .orange,
                       detail: engine.metrics.seconds > 0 ? "Max \(engine.metrics.maxPower) W" : nil)

            MetricTile(title: "Normalized", value: "\(engine.metrics.normalizedPower)", unit: "W",
                       systemImage: "waveform.path.ecg", tint: .pink,
                       detail: engine.metrics.seconds > 0
                           ? String(format: "TSS %.0f", engine.metrics.trainingStressScore(ftp: settings.ftp)) : nil)

            MetricTile(title: "Energy", value: "\(engine.metrics.kilojoules)", unit: "kJ",
                       systemImage: "flame.fill", tint: .red)
        }
    }
}
