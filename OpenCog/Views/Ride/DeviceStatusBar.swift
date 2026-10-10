import SwiftUI

/// Compact toolbar indicator: one icon per device role, coloured by connection state.
struct DeviceStatusBar: View {
    @Environment(BluetoothManager.self) private var bluetooth

    var body: some View {
        HStack(spacing: 10) {
            icon("bicycle", role: .trainer)
            clickIcon
            icon("heart.fill", role: .heartRate)
        }
        .font(.subheadline.weight(.semibold))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private func icon(_ systemImage: String, role: DeviceRole) -> some View {
        Image(systemName: systemImage)
            .foregroundStyle(color(for: bluetooth.link(for: role)?.state))
    }

    private var clickIcon: some View {
        let states = [bluetooth.link(for: .clickLeft)?.state, bluetooth.link(for: .clickRight)?.state]
        let state: LinkState? = states.contains(.ready) ? .ready : states.compactMap { $0 }.first
        return Image(systemName: "button.programmable")
            .foregroundStyle(color(for: state))
    }

    private func color(for state: LinkState?) -> Color {
        switch state {
        case .ready: return .green
        case .connecting, .handshaking: return .orange
        case .disconnected, nil: return Color(.tertiaryLabel)
        }
    }

    private var accessibilitySummary: String {
        DeviceRole.allCases.map { role in
            "\(role.title): \(bluetooth.link(for: role)?.state.title ?? "Not paired")"
        }
        .joined(separator: ", ")
    }
}
