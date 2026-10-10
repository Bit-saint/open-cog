import SwiftUI

/// The ride screen as one fixed, non-scrolling layout sized from the available space.
///
/// Landscape:                                  Portrait:
/// ┌───────────────────────────┬────────┐      ┌───────────────────────┐
/// │ Heart rate  │  Speed      │ Trainer│      │ Heart rate │ Speed    │
/// ├─────┬─────┬─────┬─────────┤ panel  │      ├────┬────┬────┬────────┤
/// │ 8 secondary metrics (4×2) │        │      │ 8 secondary (4×2)     │
/// ├───────────────────────────┤        │      ├───────────────────────┤
/// │ Live chart                │────────│      │ Live chart (if room)  │
/// │                           │ Start  │      │ Trainer panel         │
/// └───────────────────────────┴────────┘      │ Start / Pause         │
///                                             └───────────────────────┘
struct RideDashboard: View {
    @Binding var confirmingFinish: Bool

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            if size.width > size.height {
                landscape(size)
            } else {
                portrait(size)
            }
        }
    }

    // MARK: Landscape

    private func landscape(_ size: CGSize) -> some View {
        let padding: CGFloat = size.height > 500 ? 16 : 10
        let spacing: CGFloat = size.height > 500 ? 14 : 8
        let inner = CGSize(width: size.width - padding * 2, height: size.height - padding * 2)
        let sideWidth = min(320, max(240, inner.width * 0.28))
        let mainWidth = inner.width - sideWidth - spacing
        let showChart = inner.height >= 520
        let heroHeight = inner.height * (showChart ? 0.38 : 0.50)
        let secondaryHeight = inner.height * (showChart ? 0.30 : 0.50) - spacing

        return HStack(alignment: .top, spacing: spacing) {
            VStack(spacing: spacing) {
                HeroRow(spacing: spacing)
                    .frame(height: heroHeight)
                SecondaryGrid(spacing: spacing)
                    .frame(height: secondaryHeight)
                if showChart {
                    LiveChartCard()
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: mainWidth)

            VStack(spacing: spacing) {
                TrainerPanel(layout: .vertical)
                    .frame(maxHeight: .infinity)
                RideControls(confirmingFinish: $confirmingFinish)
            }
            .frame(width: sideWidth)
        }
        .padding(padding)
    }

    // MARK: Portrait

    private func portrait(_ size: CGSize) -> some View {
        let padding: CGFloat = size.width > 600 ? 16 : 12
        let spacing: CGFloat = size.width > 600 ? 14 : 8
        let inner = CGSize(width: size.width - padding * 2, height: size.height - padding * 2)
        let controlsHeight: CGFloat = 50
        let panelHeight = min(max(inner.height * 0.22, 150), 220)
        let heroHeight = inner.height * 0.24
        let secondaryHeight = inner.height * 0.22
        let used = heroHeight + secondaryHeight + panelHeight + controlsHeight + spacing * 4
        let chartHeight = inner.height - used
        let showChart = chartHeight >= 90
        // Without a chart, give its space to the hero tiles.
        let heroFinal = showChart ? heroHeight : heroHeight + max(chartHeight, 0) + spacing

        return VStack(spacing: spacing) {
            HeroRow(spacing: spacing)
                .frame(height: heroFinal)
            SecondaryGrid(spacing: spacing)
                .frame(height: secondaryHeight)
            if showChart {
                LiveChartCard()
                    .frame(height: chartHeight)
            }
            TrainerPanel(layout: .horizontal)
                .frame(height: panelHeight)
            RideControls(confirmingFinish: $confirmingFinish)
                .frame(height: controlsHeight)
        }
        .padding(padding)
    }
}

// MARK: - Hero row: heart rate (zone coloured) and speed

private struct HeroRow: View {
    var spacing: CGFloat

    @Environment(RideEngine.self) private var engine
    @Environment(AppSettings.self) private var settings
    @Environment(BluetoothManager.self) private var bluetooth

    var body: some View {
        HStack(spacing: spacing) {
            heartRate
            speed
        }
    }

    private var heartRate: some View {
        let bpm = engine.heartRate
        let zone = bpm.flatMap { TrainingZone.heartRate($0, max: settings.maxHeartRate) }
        let detail: String
        if let zone {
            detail = "Zone \(zone.number) · \(zone.name)"
        } else if bluetooth.link(for: .heartRate) == nil {
            detail = "Pair your watch in Devices"
        } else {
            detail = bluetooth.isReady(.heartRate) ? "Waiting for data…" : "Connecting…"
        }
        return DashTile(title: "Heart Rate", value: bpm.map { "\($0)" } ?? "--", unit: "bpm",
                        tint: zone?.color ?? .red, detail: detail, hero: true, tinted: zone != nil) {
            Image(systemName: "heart.fill")
                .symbolEffect(.pulse, options: .repeating, isActive: bpm != nil)
        } footer: {
            HeartRateZoneBar(current: zone?.number)
                .padding(.top, 6)
        }
    }

    private var speed: some View {
        let current = Format.speed(engine.virtualSpeed, units: settings.units)
        let average = Format.speed(engine.metrics.averageSpeed, units: settings.units)
        let max = Format.speed(engine.metrics.maxSpeed, units: settings.units)
        let detail = engine.metrics.seconds > 0
            ? "Avg \(average.value) · Max \(max.value)"
            : (engine.mode == .sim ? "Gear \(engine.gear) · \(Format.grade(engine.grade))" : "ERG \(engine.ergTarget) W")
        return DashTile(title: "Speed", value: current.value, unit: current.unit, tint: .blue,
                        detail: detail, hero: true) {
            Image(systemName: "speedometer")
        } footer: {
            EmptyView()
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

// MARK: - Secondary metrics (4 × 2)

private struct SecondaryGrid: View {
    var spacing: CGFloat

    @Environment(RideEngine.self) private var engine
    @Environment(AppSettings.self) private var settings

    var body: some View {
        VStack(spacing: spacing) {
            HStack(spacing: spacing) {
                DashTile(title: "Time", value: Format.duration(engine.metrics.seconds), unit: "",
                         systemImage: "stopwatch", tint: stateColor, detail: stateTitle)
                let distance = Format.distance(engine.metrics.distance, units: settings.units)
                DashTile(title: "Distance", value: distance.value, unit: distance.unit,
                         systemImage: "point.topleft.down.to.point.bottomright.curvepath", tint: .indigo)
                let powerZone = TrainingZone.power(engine.powerAverage3s, ftp: settings.ftp)
                DashTile(title: "Power", value: "\(engine.power)", unit: "W", systemImage: "bolt.fill",
                         tint: powerZone?.color ?? .yellow,
                         detail: powerZone.map { "Z\($0.number) · \($0.name)" } ?? "3s \(engine.powerAverage3s) W")
                DashTile(title: "Cadence", value: "\(engine.cadence)", unit: "rpm",
                         systemImage: "arrow.triangle.2.circlepath", tint: .teal, detail: "Estimated")
            }
            HStack(spacing: spacing) {
                DashTile(title: "Avg Power", value: "\(engine.metrics.averagePower)", unit: "W",
                         systemImage: "chart.bar.fill", tint: .orange,
                         detail: engine.metrics.seconds > 0 ? "Max \(engine.metrics.maxPower) W" : nil)
                DashTile(title: "Normalized", value: "\(engine.metrics.normalizedPower)", unit: "W",
                         systemImage: "waveform.path.ecg", tint: .pink,
                         detail: engine.metrics.seconds > 0
                             ? String(format: "TSS %.0f", engine.metrics.trainingStressScore(ftp: settings.ftp)) : nil)
                DashTile(title: "Energy", value: "\(engine.metrics.kilojoules)", unit: "kJ",
                         systemImage: "flame.fill", tint: .red)
                DashTile(title: "Avg HR", value: engine.metrics.averageHeartRate.map { "\($0)" } ?? "--",
                         unit: "bpm", systemImage: "heart.text.square", tint: .red,
                         detail: engine.metrics.maxHeartRate > 0 ? "Max \(engine.metrics.maxHeartRate)" : nil)
            }
        }
    }

    private var stateTitle: String {
        switch engine.state {
        case .idle: return "Ready"
        case .riding: return "Recording"
        case .paused: return "Paused"
        case .autoPaused: return "Auto-paused"
        }
    }

    private var stateColor: Color {
        switch engine.state {
        case .idle: return .gray
        case .riding: return .green
        case .paused, .autoPaused: return .orange
        }
    }
}
