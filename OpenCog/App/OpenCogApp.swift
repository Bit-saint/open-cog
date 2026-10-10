import SwiftData
import SwiftUI

@main
struct OpenCogApp: App {
    @State private var settings: AppSettings
    @State private var bluetooth: BluetoothManager
    @State private var engine: RideEngine

    init() {
        let settings = AppSettings()
        let bluetooth = BluetoothManager()
        _settings = State(initialValue: settings)
        _bluetooth = State(initialValue: bluetooth)
        _engine = State(initialValue: RideEngine(bluetooth: bluetooth, settings: settings))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(settings)
                .environment(bluetooth)
                .environment(engine)
        }
        .modelContainer(for: RideRecord.self)
    }
}
