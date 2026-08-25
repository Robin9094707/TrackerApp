import SwiftUI
import MapKit

struct HistoryView: View {
    let tracker: Tracker
    @State private var response: HistoryResponse?
    @State private var days = 7
    @State private var loading = false
    @State private var error: String?
    @State private var position: MapCameraPosition = .automatic
    @State private var selectedIndex: Double = 0

    private var chronologicalPoints: [HistoryPoint] {
        (response?.points ?? []).sorted { $0.timestamp < $1.timestamp }
    }

    private var selectedPoint: HistoryPoint? {
        let points = chronologicalPoints
        guard !points.isEmpty else { return nil }
        let index = min(max(Int(selectedIndex.rounded()), 0), points.count - 1)
        return points[index]
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Picker("Zeitraum", selection: $days) {
                    Text("24 h").tag(1)
                    Text("7 Tage").tag(7)
                    Text("30 Tage").tag(30)
                    Text("90 Tage").tag(90)
                }
                .pickerStyle(.segmented)
                .onChange(of: days) { _, _ in Task { await load() } }

                if loading && response == nil {
                    ProgressView("Standortverlauf wird geladen …")
                        .frame(maxWidth: .infinity, minHeight: 260)
                        .rjCard()
                } else if let response {
                    historyMap(response)
                    timelineCard(response)
                    summaryCard(response)
                    recentPointsCard(response)
                }
            }
            .padding()
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Standortverlauf")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .alert("Verlauf", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") {}
        } message: {
            Text(error ?? "")
        }
    }

    private func historyMap(_ response: HistoryResponse) -> some View {
        Map(position: $position) {
            let points = chronologicalPoints
            if points.count > 1 {
                MapPolyline(coordinates: points.map(\.coordinate))
                    .stroke(Color.accentColor.opacity(0.9), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            }

            if let point = selectedPoint {
                if let accuracy = point.accuracyM, accuracy > 0 {
                    MapCircle(center: point.coordinate, radius: max(accuracy, 3))
                        .foregroundStyle(Color.blue.opacity(0.16))
                        .stroke(Color.blue.opacity(0.58), lineWidth: 1.5)
                }
                Annotation("Standort", coordinate: point.coordinate, anchor: .bottom) {
                    TrackerMapBubble(tracker: tracker, selected: true)
                }
            }
        }
        .frame(height: 340)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .mapStyle(.standard(elevation: .realistic))
        .mapControls { MapCompass(); MapScaleView() }
        .overlay(alignment: .topLeading) {
            if let point = selectedPoint {
                VStack(alignment: .leading, spacing: 4) {
                    ResolvedAddressText(location: point.rjTrackerLocation, fallback: "Adresse wird ermittelt …")
                        .font(.headline)
                        .lineLimit(2)
                    HStack(spacing: 8) {
                        FreshnessLabel(timestamp: point.timestamp)
                        AccuracyPill(accuracy: point.accuracyM)
                    }
                }
                .padding(12)
                .rjGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .padding(12)
            }
        }
    }

    private func timelineCard(_ response: HistoryResponse) -> some View {
        let points = chronologicalPoints
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Zeitleiste").font(.headline)
                    if let point = selectedPoint {
                        ResolvedAddressText(location: point.rjTrackerLocation, fallback: "Adresse wird ermittelt …")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer()
                if loading { ProgressView().controlSize(.small) }
            }

            if points.count > 1 {
                Slider(value: $selectedIndex, in: 0...Double(points.count - 1), step: 1)
                    .onChange(of: selectedIndex) { _, _ in focusSelected() }

                HStack {
                    if let first = points.first {
                        Text(Date(timeIntervalSince1970: TimeInterval(first.timestamp)).formatted(date: .abbreviated, time: .omitted))
                    }
                    Spacer()
                    Text("\(Int(selectedIndex.rounded()) + 1) / \(points.count)")
                    Spacer()
                    if let last = points.last {
                        Text(Date(timeIntervalSince1970: TimeInterval(last.timestamp)).formatted(date: .abbreviated, time: .omitted))
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            } else {
                Text("Für diesen Zeitraum ist nur ein Standortpunkt vorhanden.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let point = selectedPoint {
                HStack(spacing: 12) {
                    Label(Date(timeIntervalSince1970: TimeInterval(point.timestamp)).formatted(date: .omitted, time: .shortened), systemImage: "clock")
                    if let network = point.network, !network.isEmpty {
                        Label(network.rjProviderName, systemImage: network.rjProviderSymbol)
                            .foregroundStyle(network.rjProviderColor)
                    }
                    Spacer()
                    AccuracyPill(accuracy: point.accuracyM)
                }
                .font(.caption)
            }
        }
        .rjCard()
    }

    private func summaryCard(_ response: HistoryResponse) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Zusammenfassung").font(.headline)
            let summary = response.summary
            LabeledContent("Standortmeldungen", value: "\(summary?.matchingReports ?? response.points.count)")
            LabeledContent("Aufenthalte", value: "\(summary?.confirmedStays ?? 0)")
            if let distance = summary?.distanceM { LabeledContent("Strecke", value: distance.metersText) }
            if let stay = summary?.stayText { LabeledContent("Aufenthaltszeit", value: stay) }
        }
        .rjCard()
    }

    private func recentPointsCard(_ response: HistoryResponse) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Letzte Standorte").font(.headline).padding(.bottom, 8)
            ForEach(response.points.prefix(40)) { point in
                Button { select(point) } label: {
                    HStack(spacing: 12) {
                        Circle()
                            .fill(Date(timeIntervalSince1970: TimeInterval(point.timestamp)).rjTrackerFreshnessColor)
                            .frame(width: 9, height: 9)
                        VStack(alignment: .leading, spacing: 3) {
                            ResolvedAddressText(location: point.rjTrackerLocation, fallback: "Adresse wird ermittelt …")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            HStack(spacing: 7) {
                                FreshnessLabel(timestamp: point.timestamp)
                                if let network = point.network, !network.isEmpty {
                                    Text("•").foregroundStyle(.secondary)
                                    Text(network.rjProviderName)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(network.rjProviderColor)
                                }
                                if let accuracy = point.accuracyM, accuracy > 0 {
                                    Text("±\(accuracy.metersText)").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 9)
                }
                .buttonStyle(.plain)
                Divider().padding(.leading, 21)
            }
        }
        .rjCard()
    }

    private func select(_ point: HistoryPoint) {
        let points = chronologicalPoints
        guard let index = points.firstIndex(where: { $0.id == point.id }) else { return }
        selectedIndex = Double(index)
        focusSelected()
        Haptics.impact()
    }

    private func focusSelected() {
        guard let point = selectedPoint else { return }
        let accuracy = max(point.accuracyM ?? 80, 80)
        withAnimation(.snappy(duration: 0.35)) {
            position = .region(MKCoordinateRegion(
                center: point.coordinate,
                latitudinalMeters: max(800, accuracy * 7),
                longitudinalMeters: max(800, accuracy * 7)
            ))
        }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            let loaded = try await APIClient.shared.history(tracker: tracker.ref, days: days)
            response = loaded
            let count = loaded.points.count
            selectedIndex = count > 0 ? Double(count - 1) : 0
            focusSelected()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
