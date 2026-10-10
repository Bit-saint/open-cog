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
            ScrollView {
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

    /// iPad and large iPhones in landscape: metrics on the left, controls on the right.
    private var regularLayout: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(spacing: 20) {
                RideHeader()
                MetricsGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 16)])
                LiveChartCard()
            }
            VStack(spacing: 20) {
                TrainerControlCard()
                RideControls(confirmingFinish: $confirmingFinish)
            }
            .frame(width: 360)
        }
        .padding(20)
    }

    private var compactLayout: some View {
        VStack(spacing: 16) {
            RideHeader()
            MetricsGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)])
            TrainerControlCard()
            LiveChartCard()
        }
        .padding()
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

private struct MetricsGrid: View {
    var columns: [GridItem]

    @Environment(RideEngine.self) private var engine
    @Environment(AppSettings.self) private var settings
    @Environment(BluetoothManager.self) private var bluetooth

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            let powerZone = TrainingZone.power(engine.powerAverage3s, ftp: settings.ftp)
            MetricTile(title: "Power", value: "\(engine.power)", unit: "W", systemImage: "bolt.fill",
                       tint: powerZone?.color ?? .yellow,
                       detail: powerZone.map { "Z\($0.number) · \($0.name)" } ?? "3s avg \(engine.powerAverage3s) W",
                       prominent: true)

            heartRateTile

            MetricTile(title: "Cadence", value: "\(engine.cadence)", unit: "rpm",
                       systemImage: "arrow.triangle.2.circlepath", tint: .teal,
                       detail: "Estimated from flywheel")

            let speed = Format.speed(engine.virtualSpeed, units: settings.units)
            MetricTile(title: "Speed", value: speed.value, unit: speed.unit,
                       systemImage: "speedometer", tint: .blue)

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

    private var heartRateTile: some View {
        let bpm = engine.heartRate
        let zone = bpm.flatMap { TrainingZone.heartRate($0, max: settings.maxHeartRate) }
        let detail: String
        if let zone {
            detail = "Z\(zone.number) · \(zone.name)"
        } else if bluetooth.link(for: .heartRate) == nil {
            detail = "Pair your watch in Devices"
        } else {
            detail = bluetooth.isReady(.heartRate) ? "Waiting for data…" : "Connecting…"
        }
        return MetricTile(title: "Heart Rate", value: bpm.map { "\($0)" } ?? "--", unit: "bpm",
                          tint: zone?.color ?? .red, detail: detail, prominent: true) {
            Image(systemName: "heart.fill")
                .symbolEffect(.pulse, options: .repeating, isActive: bpm != nil)
        }
    }
}
