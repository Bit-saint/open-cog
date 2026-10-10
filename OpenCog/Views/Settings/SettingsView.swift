import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        NavigationStack {
            Form {
                Section {
                    weightStepper("Rider weight", value: $settings.riderWeightKg, range: 30...200, step: 1)
                    weightStepper("Bike weight", value: $settings.bikeWeightKg, range: 4...25, step: 0.5)
                } header: {
                    Text("Rider")
                } footer: {
                    Text("Weights are sent to the trainer and decide how hard climbs feel.")
                }

                Section("Training") {
                    Stepper(value: $settings.ftp, in: 50...500, step: 5) {
                        LabeledContent("FTP", value: "\(settings.ftp) W")
                    }
                    NavigationLink {
                        HeartRateZonesView()
                    } label: {
                        let zones = settings.heartRateZones
                        LabeledContent("Heart-rate zones",
                                       value: "Max \(settings.maxHeartRate) · Z2 \(zones.lowerLimit(ofZone: 2))–\(zones.upperLimit(ofZone: 2) - 1)")
                    }
                }

                Section {
                    Stepper(value: $settings.chainringTeeth, in: 22...60) {
                        LabeledContent("Chainring", value: "\(settings.chainringTeeth)T")
                    }
                    Stepper(value: $settings.cogTeeth, in: 10...20) {
                        LabeledContent("Zwift Cog", value: "\(settings.cogTeeth)T")
                    }
                    Stepper(value: $settings.wheelCircumferenceMm, in: 1900...2300) {
                        LabeledContent("Wheel circumference", value: "\(settings.wheelCircumferenceMm) mm")
                    }
                } header: {
                    Text("Drivetrain")
                } footer: {
                    Text("The D100 doesn't report cadence, so OpenCog estimates it from flywheel speed using your chainring and the fixed Zwift Cog.")
                }

                Section("Riding") {
                    Stepper(value: $settings.startingGear, in: GearTable.range) {
                        LabeledContent("Starting gear", value: "\(settings.startingGear)")
                    }
                    Toggle("Hold shifter to keep shifting", isOn: $settings.holdToRepeat)
                    Toggle("Auto-pause when stopped", isOn: $settings.autoPause)
                    Picker("Units", selection: $settings.units) {
                        ForEach(UnitSystem.allCases) { Text($0.title).tag($0) }
                    }
                }

                Section {
                    ButtonMappingRow(button: "Right shift", action: "Harder gear · +5 W in ERG")
                    ButtonMappingRow(button: "Left shift", action: "Easier gear · −5 W in ERG")
                    ButtonMappingRow(button: "D-pad up / down", action: "Grade ±0.5 % · ±10 W in ERG")
                    ButtonMappingRow(button: "A", action: "Start · pause · resume ride")
                    ButtonMappingRow(button: "Y", action: "Switch Gears / ERG mode")
                    ButtonMappingRow(button: "B", action: "Skip to next workout step")
                } header: {
                    Text("Zwift Click Buttons")
                }

                Section("About") {
                    LabeledContent("Version", value: appVersion)
                    Text("OpenCog talks to the Van Rysel D100 with Zwift Cog using the Zwift virtual-shifting protocol, reads Zwift Click v2 controllers, and shows heart rate from any Bluetooth heart-rate broadcaster such as a Garmin watch.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
        }
    }

    private func weightStepper(_ title: String, value: Binding<Double>, range: ClosedRange<Double>,
                               step: Double) -> some View {
        let imperial = settings.units == .imperial
        let factor = imperial ? 2.204_62 : 1
        let display = Binding<Double>(
            get: { (value.wrappedValue * factor / step).rounded() * step },
            set: { value.wrappedValue = $0 / factor }
        )
        return Stepper(value: display, in: (range.lowerBound * factor)...(range.upperBound * factor), step: step) {
            LabeledContent(title, value: String(format: step < 1 ? "%.1f %@" : "%.0f %@",
                                                display.wrappedValue, imperial ? "lb" : "kg"))
        }
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}

private struct ButtonMappingRow: View {
    var button: String
    var action: String

    var body: some View {
        LabeledContent {
            Text(action)
                .multilineTextAlignment(.trailing)
        } label: {
            Text(button)
                .font(.body.weight(.medium))
        }
    }
}
