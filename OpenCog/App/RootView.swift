import SwiftUI
import UIKit

enum AppTab: Hashable {
    case ride, devices, history, settings
}

struct RootView: View {
    @Environment(RideEngine.self) private var engine
    @Environment(BluetoothManager.self) private var bluetooth
    @State private var selection: AppTab = .ride

    var body: some View {
        TabView(selection: $selection) {
            RideView(selectedTab: $selection)
                .tabItem { Label("Ride", systemImage: "bicycle") }
                .tag(AppTab.ride)

            DevicesView()
                .tabItem { Label("Devices", systemImage: "antenna.radiowaves.left.and.right") }
                .tag(AppTab.devices)

            HistoryView()
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
                .tag(AppTab.history)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(AppTab.settings)
        }
        .onChange(of: keepScreenAwake, initial: true) { _, awake in
            // Riding with the phone on the handlebars: don't let the screen lock.
            UIApplication.shared.isIdleTimerDisabled = awake
        }
    }

    private var keepScreenAwake: Bool {
        engine.state.isActive || bluetooth.isReady(.trainer)
    }
}
