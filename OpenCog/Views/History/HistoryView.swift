import SwiftData
import SwiftUI

struct HistoryView: View {
    @Query(sort: \RideRecord.date, order: .reverse) private var rides: [RideRecord]
    @Environment(\.modelContext) private var modelContext
    @Environment(AppSettings.self) private var settings

    var body: some View {
        NavigationStack {
            List {
                ForEach(rides) { ride in
                    NavigationLink(value: ride) {
                        RideRow(ride: ride, units: settings.units)
                    }
                }
                .onDelete { offsets in
                    for index in offsets { modelContext.delete(rides[index]) }
                    try? modelContext.save()
                }
            }
            .navigationTitle("History")
            .navigationDestination(for: RideRecord.self) { ride in
                RideDetailView(ride: ride)
            }
            .overlay {
                if rides.isEmpty {
                    ContentUnavailableView("No Rides Yet", systemImage: "bicycle",
                                           description: Text("Finished rides appear here."))
                }
            }
            .toolbar {
                if !rides.isEmpty { EditButton() }
            }
        }
    }
}

private struct RideRow: View {
    var ride: RideRecord
    var units: UnitSystem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(ride.date, format: .dateTime.weekday(.wide).day().month().hour().minute())
                .font(.headline)
            HStack(spacing: 16) {
                Label(Format.duration(ride.duration), systemImage: "clock")
                let distance = Format.distance(ride.distance, units: units)
                Label("\(distance.value) \(distance.unit)", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                Label("\(ride.averagePower) W", systemImage: "bolt.fill")
                if let hr = ride.averageHeartRate {
                    Label("\(hr)", systemImage: "heart.fill")
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .labelStyle(.titleAndIcon)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
        .padding(.vertical, 4)
    }
}
