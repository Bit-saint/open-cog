import SwiftUI

/// Configure max/resting heart rate, the zone method and where each zone starts.
/// Zone 2 workouts hold heart rate inside Zone 2 as set here.
struct HeartRateZonesView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        let zones = settings.heartRateZones

        Form {
            Section {
                Stepper(value: $settings.maxHeartRate, in: 120...230) {
                    LabeledContent("Max heart rate", value: "\(settings.maxHeartRate) bpm")
                }
                Picker("Zones based on", selection: $settings.heartRateZoneMethod) {
                    ForEach(HeartRateZoneMethod.allCases) { Text($0.title).tag($0) }
                }
                if settings.heartRateZoneMethod == .heartRateReserve {
                    Stepper(value: $settings.restingHeartRate, in: 30...100) {
                        LabeledContent("Resting heart rate", value: "\(settings.restingHeartRate) bpm")
                    }
                }
            } header: {
                Text("Heart Rate")
            } footer: {
                Text(settings.heartRateZoneMethod == .percentOfMax
                     ? "Zone limits are a percentage of your max heart rate, like Garmin's default zones. Use your highest heart rate seen in a hard effort or test, not 220 − age, if you can."
                     : "Zone limits are a percentage of your heart-rate reserve (max − resting). Measure resting heart rate in the morning before getting up, or take it from your Garmin.")
            }

            Section {
                ForEach(1...5, id: \.self) { zone in
                    zoneRow(zone, zones: zones)
                }
            } header: {
                Text("Zones")
            } footer: {
                Text("Adjust where each zone starts. To match your watch, copy the limits from Garmin Connect › Heart Rate Zones. Zone 2 workouts keep you inside Zone 2; VO₂max sessions count time in Zone 5.")
            }

            Section {
                Button("Reset to Default Zones") {
                    settings.heartRateZoneBoundaries = HeartRateZones.defaultBoundaries
                }
            }
        }
        .navigationTitle("Heart-Rate Zones")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func zoneRow(_ zone: Int, zones: HeartRateZones) -> some View {
        let color = TrainingZone.heartRateColors[zone - 1]
        let name = TrainingZone.heartRateNames[zone - 1]
        let range: String = {
            switch zone {
            case 1: return "< \(zones.lowerLimit(ofZone: 2)) bpm"
            case 5: return "≥ \(zones.lowerLimit(ofZone: 5)) bpm"
            default: return "\(zones.lowerLimit(ofZone: zone))–\(zones.upperLimit(ofZone: zone) - 1) bpm"
            }
        }()

        let label = HStack(spacing: 10) {
            Circle().fill(color).frame(width: 12, height: 12)
            VStack(alignment: .leading, spacing: 2) {
                Text("Zone \(zone) · \(name)").font(.body.weight(.medium))
                Text(range).font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
            }
        }

        if zone == 1 {
            label
        } else {
            let index = zone - 2
            Stepper(value: boundaryBinding(index), in: boundaryRange(index), step: 0.01) {
                HStack {
                    label
                    Spacer()
                    Text("from \(Int((settings.heartRateZoneBoundaries[index] * 100).rounded())) %")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(color)
                        .monospacedDigit()
                }
            }
        }
    }

    private func boundaryBinding(_ index: Int) -> Binding<Double> {
        Binding(
            get: { settings.heartRateZoneBoundaries[index] },
            set: { newValue in
                var values = settings.heartRateZoneBoundaries
                values[index] = (newValue * 100).rounded() / 100
                settings.heartRateZoneBoundaries = values
            }
        )
    }

    /// Each limit stays between its neighbours so zones never overlap.
    private func boundaryRange(_ index: Int) -> ClosedRange<Double> {
        let values = settings.heartRateZoneBoundaries
        let lower = index > 0 ? values[index - 1] + 0.01 : 0.40
        let upper = index < values.count - 1 ? values[index + 1] - 0.01 : 0.98
        return lower...max(lower, upper)
    }
}
