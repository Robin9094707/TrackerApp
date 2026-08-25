import SwiftUI
import MapKit

struct HistoryView: View {
    let tracker: Tracker
    @State private var response: HistoryResponse?
    @State private var days = 7
    @State private var loading = false
    @State private var error: String?
    @State private var position: MapCameraPosition = .automatic

    var body: some View {
        List {
            Section { Picker("Zeitraum", selection: $days) { Text("24 h").tag(1); Text("7 Tage").tag(7); Text("30 Tage").tag(30); Text("90 Tage").tag(90) }.pickerStyle(.segmented).onChange(of: days) { _, _ in Task { await load() } } }
            if let response {
                Section {
                    Map(position: $position) {
                        if response.points.count > 1 { MapPolyline(coordinates: response.points.reversed().map(\.coordinate)).stroke(.tint, lineWidth: 4) }
                        if let first = response.points.last { Marker("Start", systemImage: "flag.fill", coordinate: first.coordinate) }
                        if let latest = response.points.first { Marker("Aktuell", systemImage: "location.fill", coordinate: latest.coordinate) }
                    }.frame(height: 280).clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous)).mapControls { MapCompass(); MapScaleView() }
                }.listRowBackground(Color.clear)
                if let summary = response.summary {
                    Section("Zusammenfassung") { LabeledContent("Reports", value: "\(summary.matchingReports ?? 0)"); LabeledContent("Aufenthalte", value: "\(summary.confirmedStays ?? 0)"); if let distance = summary.distanceM { LabeledContent("Strecke", value: distance.metersText) }; if let stay = summary.stayText { LabeledContent("Beobachtete Aufenthaltszeit", value: stay) } }
                }
                Section("Letzte Punkte") { ForEach(response.points.prefix(100)) { point in VStack(alignment: .leading, spacing: 4) { Text(point.address?.bestText.isEmpty == false ? point.address!.bestText : "\(point.latitude), \(point.longitude)").font(.subheadline.weight(.medium)); HStack { Text(Date(timeIntervalSince1970: TimeInterval(point.timestamp)), style: .relative); Spacer(); Text(point.network ?? "") }.font(.caption).foregroundStyle(.secondary) } } }
            } else if loading { Section { ProgressView("Verlauf wird geladen …") } }
        }
        .navigationTitle("Verlauf").navigationBarTitleDisplayMode(.inline).task { await load() }
        .alert("Verlauf", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") {} } message: { Text(error ?? "") }
    }

    private func load() async { loading = true; defer { loading = false }; do { response = try await APIClient.shared.history(tracker: tracker.ref, days: days) } catch { self.error = error.localizedDescription } }
}
