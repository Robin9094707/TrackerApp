import SwiftUI
import MapKit
import UniformTypeIdentifiers

struct HistoryView: View {
    let tracker: Tracker
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var response: HistoryResponse?
    @State private var days = 7
    @State private var loading = false
    @State private var error: String?
    @State private var position: MapCameraPosition = .automatic
    @State private var selectedIndex = 0.0
    @State private var enabledNetworks: Set<String> = ["apple", "google", "samsung", "unknown", "fusion"]
    @State private var playing = false
    @State private var export = false
    @State private var exportGPX = false
    @State private var document = HistoryExportDocument(text: "")

    private var networks: [String] { Array(Set((response?.points ?? []).map { ($0.network ?? "unknown").rjNormalizedProvider })).sorted() }
    private var points: [HistoryPoint] { HistoryAnalysis.filtered(response?.points ?? [], networks: enabledNetworks) }
    private var selectedPoint: HistoryPoint? {
        guard !points.isEmpty else { return nil }
        return points[min(max(Int(selectedIndex), 0), points.count - 1)]
    }
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Picker("Zeitraum", selection: $days) {
                    Text("24 h").tag(1); Text("7 Tage").tag(7); Text("30 Tage").tag(30); Text("90 Tage").tag(90)
                }.pickerStyle(.segmented)
                if loading { ProgressView("Standortverlauf wird geladen …").frame(maxWidth: .infinity).padding() }
                if let error {
                    ContentUnavailableView("Verlauf nicht verfügbar", systemImage: "wifi.exclamationmark", description: Text(error))
                    Button("Erneut versuchen") { Task { await load() } }.buttonStyle(.bordered)
                }
                if response != nil {
                    sourceFilters
                    if points.isEmpty {
                        ContentUnavailableView("Keine Standortpunkte", systemImage: "clock", description: Text("Für diesen Zeitraum und diese Netzwerkauswahl liegen keine Meldungen vor."))
                    } else {
                        historyMap
                        playback
                        summary
                        timeline
                    }
                }
            }.padding(16)
        }
        .rjScreenChrome()
        .navigationTitle("Standortverlauf").navigationBarTitleDisplayMode(.inline)
        .task(id: days) { await load() }
        .task(id: playing) {
            guard playing else { return }
            while !Task.isCancelled, playing {
                do { try await Task.sleep(for: .seconds(0.8)) } catch { return }
                guard selectedIndex < Double(points.count - 1) else { playing = false; return }
                selectedIndex += 1
                focusSelected()
            }
        }
        .onChange(of: enabledNetworks) { _, _ in playing = false; selectedIndex = Double(max(points.count - 1, 0)); position = .automatic }
        .onDisappear { playing = false }
        .toolbar {
            Menu {
                Button("Als CSV exportieren", systemImage: "tablecells") { beginExport(gpx: false) }
                Button("Als GPX exportieren", systemImage: "point.topleft.down.to.point.bottomright.curvepath") { beginExport(gpx: true) }
            } label: { Image(systemName: "square.and.arrow.up") }
                .disabled(points.isEmpty || loading).accessibilityLabel("Verlauf exportieren")
        }
        .fileExporter(isPresented: $export, document: document, contentType: exportGPX ? .xml : .commaSeparatedText, defaultFilename: exportGPX ? "RJ-Tracker-Verlauf.gpx" : "RJ-Tracker-Verlauf.csv") { result in
            if case .failure(let failure) = result { error = failure.localizedDescription }
        }
    }

    private var sourceFilters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(networks, id: \.self) { network in
                    Button {
                        if enabledNetworks.contains(network) { enabledNetworks.remove(network) }
                        else { enabledNetworks.insert(network) }
                    } label: {
                        Label(network == "unknown" ? "Unbekannt" : network.rjProviderName, systemImage: enabledNetworks.contains(network) ? "checkmark.circle.fill" : "circle")
                    }
                    .font(.caption.weight(.semibold)).buttonStyle(.bordered).tint(enabledNetworks.contains(network) ? network.rjProviderColor : .secondary)
                }
            }
        }
    }

    private var historyMap: some View {
        Map(position: $position) {
            ForEach(HistoryAnalysis.segments(points)) { segment in
                if segment.points.count > 1 { MapPolyline(coordinates: segment.points.map(\.coordinate)).stroke(.blue, lineWidth: 3) }
            }
            if let first = points.first { Marker("Beginn", systemImage: "flag", coordinate: first.coordinate).tint(.green) }
            if let point = selectedPoint {
                if let accuracy = point.accuracyM, accuracy > 0 {
                    MapCircle(center: point.coordinate, radius: min(accuracy, 100_000)).foregroundStyle(.blue.opacity(0.12))
                }
                Annotation("Ausgewählte Meldung", coordinate: point.coordinate) {
                    Circle().fill(.blue).frame(width: 18, height: 18).overlay(Circle().stroke(.white, lineWidth: 3)).shadow(radius: 3)
                }
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .frame(height: 280).clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay(alignment: .topTrailing) {
            Button { position = .automatic } label: { Image(systemName: "arrow.up.left.and.arrow.down.right").rjGlassControl() }
                .buttonStyle(.plain).padding(12).accessibilityLabel("Gesamten Verlauf zeigen")
        }
    }

    private var playback: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let point = selectedPoint {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(Date(timeIntervalSince1970: TimeInterval(point.timestamp)).formatted(date: .abbreviated, time: .standard)).font(.headline)
                        Text("\((point.network ?? "unknown").rjProviderName) · \(Int(selectedIndex) + 1) von \(points.count)").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        if selectedIndex >= Double(points.count - 1) { selectedIndex = 0 }
                        playing.toggle()
                    } label: { Image(systemName: playing ? "pause.fill" : "play.fill").frame(width: 44, height: 44) }
                        .buttonStyle(.bordered).disabled(points.count < 2).accessibilityLabel(playing ? "Wiedergabe pausieren" : "Verlauf abspielen")
                }
                if points.count > 1 {
                    Slider(value: $selectedIndex, in: 0...Double(points.count - 1), step: 1) { editing in if editing { playing = false } }
                        .onChange(of: selectedIndex) { _, _ in focusSelected() }.accessibilityLabel("Standortmeldung auswählen")
                }
                ResolvedAddressText(location: point.rjTrackerLocation, fallback: "Adresse nicht verfügbar").font(.subheadline)
                AccuracyPill(accuracy: point.accuracyM)
            }
        }.rjCard()
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(points.count) angezeigte Meldungen").font(.headline)
            if let total = response?.matchingTotal, total > (response?.points.count ?? 0) {
                Text("Der Server hat \(response?.points.count ?? 0) von \(total) Treffern geliefert. Wähle für mehr Details einen kürzeren Zeitraum.").font(.footnote).foregroundStyle(.orange)
            }
            Text("Linien verbinden Beobachtungen. Längere Lücken und unplausible Sprünge bleiben unterbrochen. Der Export enthält die angezeigte Netzwerkauswahl.").font(.footnote).foregroundStyle(.secondary)
        }.rjCard()
    }

    private var timeline: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Letzte Meldungen").font(.headline).padding(.bottom, 8)
            ForEach(Array(points.suffix(60).reversed())) { point in
                Button {
                    playing = false
                    if let index = points.firstIndex(where: { $0.id == point.id }) { selectedIndex = Double(index) }
                } label: {
                    HStack(spacing: 12) {
                        Circle().fill((point.network ?? "unknown").rjProviderColor).frame(width: 8, height: 8)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(Date(timeIntervalSince1970: TimeInterval(point.timestamp)).formatted(date: .abbreviated, time: .shortened)).font(.subheadline.weight(.medium))
                            Text("\((point.network ?? "unknown").rjProviderName) · \(point.accuracyM.map { "±" + $0.metersText } ?? "Genauigkeit unbekannt")").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if point.id == selectedPoint?.id { Image(systemName: "checkmark").foregroundStyle(.blue) }
                    }.foregroundStyle(.primary).padding(.vertical, 12).contentShape(Rectangle())
                }.buttonStyle(.plain)
                Divider()
            }
        }.rjCard()
    }

    private func focusSelected() {
        guard let point = selectedPoint else { return }
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) {
            position = .region(RJMapCamera.focusedRegion(for: point.rjTrackerLocation, zoomMeters: max(1200, (point.accuracyM ?? 100) * 6)))
        }
    }
    private func beginExport(gpx: Bool) {
        playing = false; exportGPX = gpx
        document = HistoryExportDocument(text: gpx ? HistoryAnalysis.gpx(points) : HistoryAnalysis.csv(points))
        export = true
    }
    private func load() async {
        loading = true; error = nil; playing = false; response = nil
        let requestedDays = days
        do {
            let loaded = try await APIClient.shared.history(tracker: tracker.ref, days: requestedDays)
            guard !Task.isCancelled, requestedDays == days else { return }
            response = loaded
            enabledNetworks = Set(loaded.points.map { ($0.network ?? "unknown").rjNormalizedProvider })
            selectedIndex = Double(max(points.count - 1, 0)); position = .automatic
        } catch {
            guard !Task.isCancelled, requestedDays == days else { return }
            self.error = error.localizedDescription
        }
        loading = false
    }
}
