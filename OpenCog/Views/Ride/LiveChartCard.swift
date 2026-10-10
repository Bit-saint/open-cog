import Charts
import SwiftUI

/// Rolling 5-minute power and heart-rate charts.
struct LiveChartCard: View {
    @Environment(RideEngine.self) private var engine

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Last 5 Minutes")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            Chart(engine.liveHistory) { point in
                AreaMark(x: .value("Time", point.time), y: .value("Power", point.power))
                    .foregroundStyle(.linearGradient(colors: [.yellow.opacity(0.35), .yellow.opacity(0.02)],
                                                     startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Time", point.time), y: .value("Power", point.power))
                    .foregroundStyle(.orange)
                    .interpolationMethod(.monotone)
            }
            .chartXAxis(.hidden)
            .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) }
            .chartYAxisLabel("W")
            .frame(minHeight: 30, maxHeight: .infinity)
            .layoutPriority(1)

            Chart(engine.liveHistory.filter { $0.heartRate != nil }) { point in
                LineMark(x: .value("Time", point.time), y: .value("Heart Rate", point.heartRate ?? 0))
                    .foregroundStyle(.red)
                    .interpolationMethod(.monotone)
            }
            .chartXAxis(.hidden)
            .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) }
            .chartYScale(domain: .automatic(includesZero: false))
            .chartYAxisLabel("bpm")
            .frame(minHeight: 24, maxHeight: .infinity)
        }
        .card(padding: 12)
        .frame(maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Power and heart rate for the last five minutes")
    }
}
