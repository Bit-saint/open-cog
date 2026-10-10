import SwiftData
import SwiftUI

struct RideView: View {
    @Binding var selectedTab: AppTab

    @Environment(RideEngine.self) private var engine
    @Environment(\.modelContext) private var modelContext

    @State private var confirmingFinish = false
    @State private var finishedRide: RideRecord?
    @State private var visibleFeedback: ControlFeedback?

    var body: some View {
        NavigationStack {
            RideDashboard(confirmingFinish: $confirmingFinish)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Ride")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { selectedTab = .devices } label: { DeviceStatusBar() }
                        .accessibilityHint("Opens Devices")
                }
            }
            .overlay(alignment: .top) { feedbackToast }
            .confirmationDialog("Finish this ride?", isPresented: $confirmingFinish, titleVisibility: .visible) {
                Button("Save Ride") { saveRide() }
                Button("Discard Ride", role: .destructive) { engine.discard() }
                Button("Keep Riding", role: .cancel) {}
            }
            .sheet(item: $finishedRide) { ride in
                NavigationStack {
                    RideDetailView(ride: ride)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { finishedRide = nil }
                            }
                        }
                }
            }
        }
        .sensoryFeedback(.selection, trigger: engine.gear)
        .sensoryFeedback(.impact(weight: .medium), trigger: engine.state)
        .onChange(of: engine.feedback) { _, feedback in
            guard let feedback else { return }
            withAnimation(.snappy) { visibleFeedback = feedback }
            Task {
                try? await Task.sleep(for: .seconds(1.2))
                if visibleFeedback?.id == feedback.id {
                    withAnimation(.easeOut) { visibleFeedback = nil }
                }
            }
        }
    }

    @ViewBuilder
    private var feedbackToast: some View {
        if let feedback = visibleFeedback {
            Label(feedback.text, systemImage: feedback.systemImage)
                .font(.headline)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(.regularMaterial, in: Capsule())
                .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .id(feedback.id)
        }
    }

    private func saveRide() {
        guard let record = engine.finish() else { return }
        modelContext.insert(record)
        try? modelContext.save()
        finishedRide = record
    }
}
