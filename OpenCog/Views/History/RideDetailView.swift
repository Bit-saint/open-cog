import Charts
import SwiftUI

struct RideDetailView: View {
    var ride: RideRecord

    @Environment(AppSettings.self) private var settings
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var samples: [RideSample] = []
    @State private var exportURL: URL?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let name = ride.workoutName {
                    Label(name, systemImage: "list.bullet.rectangle.portrait")
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                LazyVGrid(columns: columns, spacing: 12) {
                    stat("Duration", Format.duration(ride.duration), "", "clock", .blue)
                    let distance = Format.distance(ride.distance, units: settings.units)
                    stat("Distance", distance.value, distance.unit, "point.topleft.down.to.point.bottomright.curvepath", .indigo)
                    stat("Avg Power", "\(ride.averagePower)", "W", "bolt.fill", .orange)
                    stat("Normalized", "\(ride.normalizedPower)", "W", "waveform.path.ecg", .pink)
                    stat("Max Power", "\(ride.maxPower)", "W", "bolt.horizontal.fill", .yellow)
                    stat("Avg HR", ride.averageHeartRate.map { "\($0)" } ?? "--", "bpm", "heart.fill", .red)
                    stat("Max HR", ride.maxHeartRate.map { "\($0)" } ?? "--", "bpm", "heart.circle.fill", .red)
                    stat("Cadence", "\(ride.averageCadence)", "rpm", "arrow.triangle.2.circlepath", .teal)
                    stat("Energy", "\(ride.kilojoules)", "kJ", "flame.fill", .red)
                    stat("TSS", String(format: "%.0f", ride.tss), "", "gauge.with.dots.needle.67percent", .purple)
                }

                if !samples.isEmpty {
                    analysisCard
                    powerChart.card()
                    if samples.contains(where: { $0.heartRate != nil }) {
                        heartRateChart.card()
                    }
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(ride.date.formatted(date: .abbreviated, time: .shortened))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if let exportURL {
                    ShareLink(item: exportURL) {
                        Label("Export TCX", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
        .task(id: ride.id) {
            samples = ride.samples
            exportURL = try? TCXExporter.writeFile(for: ride, samples: samples)
        }
    }

    private var analysis: RideAnalysis {
        RideAnalysis(samples: samples, zones: settings.heartRateZones, ftp: ride.ftp)
    }

    /// Time in heart-rate zones, estimated fat burned and aerobic decoupling.
    private var analysisCard: some View {
        let result = analysis
        let totalHR = max(result.heartRateZoneSeconds.reduce(0, +), 1)
        return VStack(alignment: .leading, spacing: 12) {
            Text("Heart-Rate Zones").font(.headline)
            if result.heartRateZoneSeconds.reduce(0, +) == 0 {
                Text("No heart-rate data in this ride.").foregroundStyle(.secondary)
            } else {
                ForEach(0..<5, id: \.self) { index in
                    let seconds = result.heartRateZoneSeconds[index]
                    HStack(spacing: 10) {
                        Text("Z\(index + 1)")
                            .font(.subheadline.weight(.semibold))
                            .frame(width: 28, alignment: .leading)
                        GeometryReader { geo in
                            Capsule()
                                .fill(TrainingZone.heartRateColors[index].gradient)
                                .frame(width: max(geo.size.width * Double(seconds) / Double(totalHR), seconds > 0 ? 4 : 0))
                        }
                        .frame(height: 12)
                        Text(Format.duration(seconds))
                            .font(.subheadline)
                            .monospacedDigit()
                            .frame(width: 64, alignment: .trailing)
                    }
                }
            }

            Divider()

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Fat burned").font(.caption).foregroundStyle(.secondary)
                    Text(String(format: "≈ %.0f g", result.fatGrams)).font(.title3.weight(.semibold))
                    Text(String(format: "%.0f kcal · %.0f g carbs", result.kilocalories, result.carbGrams))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Aerobic decoupling").font(.caption).foregroundStyle(.secondary)
                    if let drift = result.decouplingPercent {
                        Text(String(format: "%.1f %%", drift))
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(drift < 5 ? .green : .orange)
                        Text(drift < 5 ? "Solid aerobic base" : "Heart rate drifted up")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("—").font(.title3.weight(.semibold))
                        Text("Needs 20+ min with HR").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Text("Fat and carbohydrate are estimates from power and FTP; individual values vary.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .card()
    }

    private var columns: [GridItem] {
        horizontalSizeClass == .regular
            ? [GridItem(.adaptive(minimum: 170), spacing: 12)]
            : [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
    }

    private func stat(_ title: String, _ value: String, _ unit: String, _ symbol: String, _ tint: Color) -> some View {
        MetricTile(title: title, value: value, unit: unit, systemImage: symbol, tint: tint)
    }

    /// At most ~600 points so long rides stay fast to draw.
    private var chartSamples: [RideSample] {
        let stride = max(1, samples.count / 600)
        return Swift.stride(from: 0, to: samples.count, by: stride).map { samples[$0] }
    }

    private var powerChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Power").font(.headline)
            Chart {
                ForEach(chartSamples, id: \.t) { sample in
                    LineMark(x: .value("Minutes", Double(sample.t) / 60), y: .value("Watts", sample.power))
                        .foregroundStyle(.orange)
                        .interpolationMethod(.monotone)
                }
                RuleMark(y: .value("Average", ride.averagePower))
                    .foregroundStyle(.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .annotation(position: .top, alignment: .leading) {
                        Text("avg \(ride.averagePower) W").font(.caption2).foregroundStyle(.secondary)
                    }
            }
            .chartXAxisLabel("min")
            .frame(height: 180)
        }
    }

    private var heartRateChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Heart Rate").font(.headline)
            Chart(chartSamples.filter { $0.heartRate != nil }, id: \.t) { sample in
                LineMark(x: .value("Minutes", Double(sample.t) / 60), y: .value("bpm", sample.heartRate ?? 0))
                    .foregroundStyle(.red)
                    .interpolationMethod(.monotone)
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .chartXAxisLabel("min")
            .frame(height: 150)
        }
    }
}
