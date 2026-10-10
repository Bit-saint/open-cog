import CoreBluetooth
import SwiftUI

struct DevicesView: View {
    @Environment(BluetoothManager.self) private var bluetooth

    var body: some View {
        NavigationStack {
            List {
                if let problem = bluetoothProblem {
                    Section {
                        Label(problem, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }

                Section {
                    DeviceRow(role: .trainer)
                    candidates(for: [.trainer])
                } header: {
                    Text("Trainer")
                } footer: {
                    Text("Van Rysel D100 with Zwift Cog. Close Zwift on other devices so the trainer is free to connect.")
                }

                Section {
                    DeviceRow(role: .clickLeft)
                    DeviceRow(role: .clickRight)
                    candidates(for: [.clickLeft, .clickRight])
                } header: {
                    Text("Zwift Click")
                } footer: {
                    Text("Press any button to wake a Click. The left half also relays the right half's presses, so one half is enough to shift both ways.")
                }

                Section {
                    DeviceRow(role: .heartRate)
                    candidates(for: [.heartRate])
                } header: {
                    Text("Heart Rate")
                } footer: {
                    Text("On your Garmin watch, turn on Broadcast Heart Rate (hold MENU or open the controls menu, then choose Broadcast Heart Rate). The watch then appears here; tap it to connect. OpenCog remembers it for next time.")
                }
            }
            .navigationTitle("Devices")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if bluetooth.isScanning {
                        HStack(spacing: 6) {
                            ProgressView()
                            Text("Scanning")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Button("Scan") { bluetooth.startScanning() }
                            .disabled(!bluetooth.isPoweredOn)
                    }
                }
            }
            .onAppear { bluetooth.startScanning() }
        }
    }

    @ViewBuilder
    private func candidates(for roles: Set<DeviceRole>) -> some View {
        let assigned = Set(DeviceRole.allCases.compactMap { bluetooth.link(for: $0)?.id })
        let devices = bluetooth.discovered.values
            .filter { roles.contains($0.role) && !assigned.contains($0.id) }
            .sorted { $0.rssi > $1.rssi }
        ForEach(devices) { device in
            Button { bluetooth.connect(deviceID: device.id) } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(device.name)
                            .foregroundStyle(.primary)
                        Text(device.role.title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "cellularbars", variableValue: signalStrength(device.rssi))
                        .foregroundStyle(.secondary)
                    Text("Connect")
                        .font(.subheadline.weight(.semibold))
                }
            }
            .accessibilityLabel("Connect \(device.name)")
        }
    }

    private func signalStrength(_ rssi: Int) -> Double {
        min(max(Double(rssi + 95) / 45, 0), 1)
    }

    private var bluetoothProblem: String? {
        switch bluetooth.managerState {
        case .poweredOn, .unknown, .resetting: return nil
        case .poweredOff: return "Bluetooth is turned off. Turn it on in Control Center or Settings."
        case .unauthorized: return "OpenCog doesn't have Bluetooth permission. Allow it in Settings › Privacy & Security › Bluetooth."
        case .unsupported: return "This device doesn't support Bluetooth Low Energy."
        @unknown default: return nil
        }
    }
}

private struct DeviceRow: View {
    var role: DeviceRole
    @Environment(BluetoothManager.self) private var bluetooth

    var body: some View {
        let link = bluetooth.link(for: role)
        HStack(spacing: 14) {
            Image(systemName: role.systemImage)
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(iconColor(link?.state), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(link?.name ?? role.title)
                    .font(.body.weight(.medium))
                Text(statusText(link))
                    .font(.subheadline)
                    .foregroundStyle(link?.state == .ready ? Color.green : Color.secondary)
            }

            Spacer()

            if let battery = link?.battery {
                Label("\(battery)%", systemImage: batterySymbol(battery))
                    .font(.subheadline)
                    .foregroundStyle(battery <= 20 ? Color.red : Color.secondary)
                    .labelStyle(.titleAndIcon)
            }
            if link?.state == .connecting || link?.state == .handshaking {
                ProgressView()
            }
        }
        .padding(.vertical, 2)
        .swipeActions {
            if link != nil {
                Button("Forget", role: .destructive) { bluetooth.forget(role) }
            }
        }
        .contextMenu {
            if link != nil {
                Button("Forget Device", systemImage: "xmark.circle", role: .destructive) { bluetooth.forget(role) }
            }
        }
    }

    private func statusText(_ link: DeviceLink?) -> String {
        guard let link else {
            return role == .heartRate ? "Not paired" : "Searching…"
        }
        if link.state == .connecting && role.clickSide != nil {
            return "Waiting — press a button to wake"
        }
        return link.state.title
    }

    private func iconColor(_ state: LinkState?) -> Color {
        switch state {
        case .ready: return role == .heartRate ? .red : .accentColor
        case .connecting, .handshaking: return .orange
        case .disconnected, nil: return .gray
        }
    }

    private func batterySymbol(_ percent: Int) -> String {
        switch percent {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }
}
