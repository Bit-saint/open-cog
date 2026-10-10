import SwiftUI
import UIKit

/// Live Bluetooth state and event log, for troubleshooting a device that connects
/// but doesn't respond. "Share Report" produces plain text to send to a developer.
struct DiagnosticsView: View {
    @Environment(BluetoothManager.self) private var bluetooth
    @Environment(RideEngine.self) private var engine
    @State private var copied = false

    var body: some View {
        List {
            Section("Live Trainer Data") {
                LabeledContent("Data source", value: engine.dataSource ?? "None")
                LabeledContent("Power", value: "\(engine.power) W")
                LabeledContent("Flywheel speed", value: String(format: "%.2f m/s", engine.flywheelSpeed))
                LabeledContent("Cadence", value: "\(engine.cadence) rpm")
                LabeledContent("Mode", value: engine.mode == .sim
                    ? "Gears · gear \(engine.gear) · grade \(Format.grade(engine.grade))"
                    : "ERG · \(engine.ergTarget) W")
            }

            ForEach(DeviceRole.allCases) { role in
                Section(role.title) {
                    if let link = bluetooth.link(for: role) {
                        let stats = bluetooth.stats[role] ?? LinkStats()
                        LabeledContent("Device", value: link.name)
                        LabeledContent("State", value: link.state.title)
                        if role.usesZwiftProtocol {
                            LabeledContent("Handshake", value: stats.handshakeConfirmed
                                ? "Confirmed"
                                : "\(stats.handshakeAttempts) attempt(s), no reply")
                        }
                        LabeledContent("Services", value: stats.services.isEmpty ? "-" : stats.services.joined(separator: ", "))
                        LabeledContent("Notifying", value: stats.notifying.isEmpty ? "-" : stats.notifying.joined(separator: ", "))
                        LabeledContent("Packets received", value: "\(stats.packetsReceived)")
                        if let last = stats.lastPacket {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Last packet").font(.caption).foregroundStyle(.secondary)
                                Text(last).font(.caption.monospaced()).textSelection(.enabled)
                            }
                        }
                        if role == .trainer {
                            LabeledContent("Commands sent", value: "\(stats.commandsWritten)")
                            if let last = stats.lastCommand {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Last command").font(.caption).foregroundStyle(.secondary)
                                    Text(last).font(.caption.monospaced()).textSelection(.enabled)
                                }
                            }
                        }
                    } else {
                        Text("Not paired").foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                if bluetooth.eventLog.isEmpty {
                    Text("No events yet").foregroundStyle(.secondary)
                }
                ForEach(bluetooth.eventLog.reversed()) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(entry.date, format: .dateTime.hour().minute().second())
                            if let role = entry.role { Text(role.title) }
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        Text(entry.text)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                }
            } header: {
                Text("Event Log")
            } footer: {
                Text("Newest first. Use Share Report to send this to whoever is helping you debug.")
            }
        }
        .navigationTitle("Diagnostics")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button(copied ? "Copied" : "Copy") {
                    UIPasteboard.general.string = bluetooth.diagnosticsReport()
                    copied = true
                }
                ShareLink(item: bluetooth.diagnosticsReport()) {
                    Label("Share Report", systemImage: "square.and.arrow.up")
                }
            }
        }
    }
}
