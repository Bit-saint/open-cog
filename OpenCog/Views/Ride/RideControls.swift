import SwiftUI

/// Start / pause / resume / finish buttons.
struct RideControls: View {
    @Binding var confirmingFinish: Bool
    @Environment(RideEngine.self) private var engine

    var body: some View {
        HStack(spacing: 12) {
            switch engine.state {
            case .idle:
                Button { engine.start() } label: {
                    Label("Start Ride", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)

            case .riding, .autoPaused:
                Button { engine.pause() } label: {
                    Label("Pause", systemImage: "pause.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                finishButton

            case .paused:
                Button { engine.resume() } label: {
                    Label("Resume", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)

                finishButton
            }
        }
        .controlSize(.large)
        .font(.headline)
        .animation(.snappy, value: engine.state)
    }

    private var finishButton: some View {
        Button { confirmingFinish = true } label: {
            Label("Finish", systemImage: "flag.checkered")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(.red)
    }
}
