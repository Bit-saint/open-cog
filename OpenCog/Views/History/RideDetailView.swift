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
