import SwiftUI
import MapKit
import UniformTypeIdentifiers

struct HistoryView: View {
    let tracker: Tracker
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.rjExpandInspector) private var expandInspector
    @AppStorage("historyPeriodDays") private var days = 1
    @State private var response: HistoryResponse?
    @State private var loadedDays: Int?
    @State private var prepared = PreparedHistory()
    @State private var timelineLimit = 60
    @State private var loadID = UUID()
    @State private var preparationID = UUID()
    @State private var loading = false
    @State private var preparing = false
    @State private var error: String?
    @State private var position: MapCameraPosition = .automatic
    @State private var selectedIndex = 0
    @State private var selectedDay: Date?
    @State private var enabledNetworks: Set<String> = []
    @State private var playing = false
    @State private var speed = 1.0
    @State private var export = false
    @State private var exportGPX = false
    @State private var document = HistoryExportDocument(text: "")
    @State private var showStays = false

    private var points: [HistoryPoint] { prepared.points }
    private var selectedPoint: HistoryPoint? {
        guard !points.isEmpty else { return nil }
        return points[min(max(selectedIndex, 0), points.count - 1)]
    }
    private var networks: [String] {
        Array(Set((response?.points ?? []).map { ($0.network ?? "unknown").rjNormalizedProvider })).sorted()
    }
    private var visibleDays: [HistoryDay] {
        let filtered = prepared.days.filter { selectedDay == nil || $0.date == selectedDay }
        var remaining = timelineLimit
        return filtered.compactMap { day in
            guard remaining > 0 else { return nil }
            let visible = Array(day.points.prefix(remaining)); remaining -= visible.count
            return HistoryDay(date: day.date, points: visible)
        }
    }
    private var timelineCount: Int {
        selectedDay.flatMap { date in prepared.days.first { $0.date == date }?.points.count } ?? points.count
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 18) {
                    periodPicker
                    if loading || preparing {
                        HStack(spacing: 10) {
                            ProgressView().controlSize(.small)
                            Text(response == nil ? "Verlauf wird geladen …" : "Verlauf wird aktualisiert …").font(.subheadline)
                            Spacer()
                        }.padding(.horizontal, 6).accessibilityIdentifier("history-loading")
                    }
                    if let error {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Verlauf konnte nicht aktualisiert werden", systemImage: "wifi.exclamationmark").font(.headline)
                            Text(error).font(.footnote).foregroundStyle(.secondary)
                            Button("Erneut versuchen") { Task { await load(force: true) } }.buttonStyle(.bordered)
                        }.rjCard()
                    }
                    if response != nil {
                        if let loadedDays, loadedDays != days {
                            Label("Angezeigt: letzter erfolgreich geladener Zeitraum (\(loadedDays) Tage).", systemImage: "clock.badge.exclamationmark")
                                .font(.footnote).foregroundStyle(.orange)
                        }
                        sourceFilters
                        if points.isEmpty {
                            ContentUnavailableView("Keine Standortpunkte", systemImage: "clock", description: Text("Für diesen Zeitraum und diese Netzwerkauswahl liegen keine Meldungen vor."))
                        } else {
                            historyMap.id("history-map")
                            playback
                            summary
                            if !(response?.stays ?? []).isEmpty { staysCard }
                            dayPicker
                            timeline(proxy: proxy)
                        }
                    }
                }.padding(16).frame(maxWidth: 850).frame(maxWidth: .infinity)
            }
        }
        .rjScreenChrome()
        .navigationTitle("Standortverlauf").navigationBarTitleDisplayMode(.inline)
        .task(id: days) { await load() }
        .onAppear { expandInspector() }
        .refreshable { await load(force: true) }
        .task(id: playing) {
            guard playing else { return }
            while !Task.isCancelled, playing {
                do { try await Task.sleep(for: .seconds(0.9 / speed)) } catch { return }
                guard selectedIndex < points.count - 1 else { playing = false; return }
                selectedIndex += 1
                focusSelected()
            }
        }
        .onDisappear { playing = false }
        .toolbar {
            Menu {
                Button("Als CSV exportieren", systemImage: "tablecells") { beginExport(gpx: false) }
                Button("Als GPX exportieren", systemImage: "point.topleft.down.to.point.bottomright.curvepath") { beginExport(gpx: true) }
            } label: { Image(systemName: "square.and.arrow.up") }
                .disabled(points.isEmpty || loading || preparing).accessibilityLabel("Verlauf exportieren")
        }
        .fileExporter(isPresented: $export, document: document, contentType: exportGPX ? .rjGPX : .commaSeparatedText,
                      defaultFilename: exportGPX ? "RJ-Tracker-Verlauf.gpx" : "RJ-Tracker-Verlauf.csv") { result in
            if case .failure(let failure) = result { error = failure.localizedDescription }
        }
    }

    private var periodPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(tracker.name).font(.title2.bold())
            Text("Jede Meldung im richtigen Moment.").font(.subheadline).foregroundStyle(.secondary)
            Picker("Zeitraum", selection: $days) {
                Text("24 h").tag(1); Text("7 T.").tag(7); Text("14 T.").tag(14); Text("30 T.").tag(30); Text("90 T.").tag(90)
            }.pickerStyle(.segmented).padding(.top, 4)
        }
    }

    private var sourceFilters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(networks, id: \.self) { network in
                    Button {
                        playing = false
                        if enabledNetworks.contains(network) { enabledNetworks.remove(network) }
                        else { enabledNetworks.insert(network) }
                        Task { await prepare(preserveSelection: true) }
                    } label: {
                        Label(network == "unknown" ? "Unbekannt" : network.rjProviderName,
                              systemImage: enabledNetworks.contains(network) ? "checkmark.circle.fill" : "circle")
                            .padding(.vertical, 3)
                    }
                    .font(.caption.weight(.semibold)).buttonStyle(.bordered).buttonBorderShape(.capsule)
                    .tint(enabledNetworks.contains(network) ? network.rjProviderColor : .secondary)
                    .accessibilityValue(enabledNetworks.contains(network) ? "Ausgewählt" : "Ausgeblendet")
                    .disabled(loading)
                }
            }
        }
    }

    private var historyMap: some View {
        Map(position: $position) {
            ForEach(prepared.mapSegments) { segment in
                if segment.points.count > 1 {
                    MapPolyline(coordinates: segment.points.map(\.coordinate))
                        .stroke((segment.points.first?.network ?? "unknown").rjProviderColor.opacity(0.75), lineWidth: 3)
                }
            }
            ForEach(prepared.mapPoints) { point in
                Annotation("Standortmeldung", coordinate: point.coordinate) {
                    Button { select(point) } label: {
                        Circle().fill((point.network ?? "unknown").rjProviderColor)
                            .frame(width: 8, height: 8).overlay(Circle().stroke(.white, lineWidth: 1.5))
                            .frame(width: 32, height: 32).contentShape(Circle())
                    }.buttonStyle(.plain)
                        .accessibilityLabel("Meldung \(Date(timeIntervalSince1970: TimeInterval(point.timestamp)).rjTimelineText)")
                }
            }
            if let first = points.first { Marker("Beginn", systemImage: "flag", coordinate: first.coordinate).tint(.green) }
            if let last = points.last { Marker("Letzte Meldung", systemImage: "flag.checkered", coordinate: last.coordinate).tint(.orange) }
            if let point = selectedPoint {
                if let accuracy = point.accuracyM, accuracy > 0 {
                    MapCircle(center: point.coordinate, radius: min(accuracy, 100_000)).foregroundStyle(.blue.opacity(0.1))
                        .stroke(.blue.opacity(0.25), lineWidth: 1)
                }
                Annotation("Ausgewählte Meldung", coordinate: point.coordinate) {
                    Circle().fill(.blue).frame(width: 18, height: 18)
                        .overlay(Circle().stroke(.white, lineWidth: 3)).shadow(color: .blue.opacity(0.4), radius: 8)
                }
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .annotationTitles(.hidden)
        .frame(height: 310).clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(alignment: .topTrailing) {
            Button { playing = false; position = .automatic } label: { Image(systemName: "arrow.up.left.and.arrow.down.right").rjGlassControl() }
                .buttonStyle(.plain).padding(12).accessibilityLabel("Gesamten Verlauf zeigen")
        }
        .overlay(alignment: .bottomLeading) {
            Text("\(points.count) Meldungen").font(.caption.weight(.semibold))
                .padding(.horizontal, 12).padding(.vertical, 8).rjGlass(in: Capsule()).padding(12)
        }
    }

    private var playback: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let point = selectedPoint {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(Date(timeIntervalSince1970: TimeInterval(point.timestamp)), style: .date).font(.caption).foregroundStyle(.secondary)
                        Text(Date(timeIntervalSince1970: TimeInterval(point.timestamp)), style: .time)
                            .font(.title2.bold()).monospacedDigit().contentTransition(.numericText())
                    }
                    Spacer()
                    ProviderBadge(provider: point.network ?? "unknown")
                }
                if let first = points.first, let last = points.last, first.timestamp < last.timestamp {
                    Slider(value: Binding(get: { Double(selectedPoint?.timestamp ?? first.timestamp) }, set: { value in
                        selectedIndex = HistoryAnalysis.nearestIndex(to: value, in: points); focusSelected()
                    }), in: Double(first.timestamp)...Double(last.timestamp)) { editing in if editing { playing = false } }
                        .accessibilityLabel("Zeitpunkt auf der Zeitleiste auswählen")
                    HStack {
                        Text(Date(timeIntervalSince1970: TimeInterval(first.timestamp)).formatted(date: .abbreviated, time: .shortened))
                        Spacer()
                        Text(Date(timeIntervalSince1970: TimeInterval(last.timestamp)).formatted(date: .abbreviated, time: .shortened))
                    }.font(.caption2).foregroundStyle(.secondary)
                }
                HStack {
                    Button { step(-1) } label: { Image(systemName: "backward.end.fill").frame(width: 44, height: 44) }
                        .disabled(selectedIndex == 0).accessibilityLabel("Vorherige Meldung")
                    Spacer()
                    Button {
                        if selectedIndex >= points.count - 1 { selectedIndex = 0; focusSelected() }
                        playing.toggle()
                    } label: { Image(systemName: playing ? "pause.fill" : "play.fill").rjGlassControl() }
                        .disabled(points.count < 2).accessibilityLabel(playing ? "Wiedergabe pausieren" : "Verlauf abspielen")
                    Spacer()
                    Button { step(1) } label: { Image(systemName: "forward.end.fill").frame(width: 44, height: 44) }
                        .disabled(selectedIndex >= points.count - 1).accessibilityLabel("Nächste Meldung")
                    Menu {
                        Picker("Geschwindigkeit", selection: $speed) {
                            Text("0,5×").tag(0.5); Text("1×").tag(1.0); Text("2×").tag(2.0); Text("4×").tag(4.0)
                        }
                    } label: { Text(speed.formatted(.number.precision(.fractionLength(0...1))) + "×").font(.caption.bold()).frame(minWidth: 44, minHeight: 44) }
                        .accessibilityLabel("Wiedergabegeschwindigkeit")
                }.buttonStyle(.plain)
                Divider()
                ResolvedAddressText(location: point.rjTrackerLocation, fallback: String(format: "%.5f, %.5f", point.latitude, point.longitude)).font(.subheadline)
                HStack {
                    AccuracyPill(accuracy: point.accuracyM)
                    Spacer()
                    Text("\(selectedIndex + 1) / \(points.count)").font(.caption).monospacedDigit().foregroundStyle(.secondary)
                }
            }
        }.rjCard()
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 12) {
            RJSectionTitle(title: "Dein Verlauf", subtitle: "\(points.count) Meldungen · \(prepared.days.count) Tage", symbol: "chart.xyaxis.line")
            if let total = response?.matchingTotal, total > (response?.points.count ?? 0) {
                Label("Die neuesten \(response?.points.count ?? 0) von \(total) Meldungen sind geladen. Der Export enthält diesen Ausschnitt.", systemImage: "info.circle")
                    .font(.footnote).foregroundStyle(.orange)
            }
            Text("Farben zeigen das Ortungsnetz. Linien verbinden Meldungen derselben Quelle. Lücken und unplausible Sprünge bleiben unterbrochen.")
                .font(.footnote).foregroundStyle(.secondary)
        }.rjCard()
    }

    private var staysCard: some View {
        DisclosureGroup(isExpanded: $showStays) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Serverauswertung für den gesamten geladenen Zeitraum, über alle Netze. Aufenthalte sind aus Meldungen abgeleitet.")
                    .font(.footnote).foregroundStyle(.secondary)
                ForEach(Array((response?.stays ?? []).prefix(50).enumerated()), id: \.offset) { _, stay in
                    HistoryStayRow(stay: stay)
                }
                if (response?.stays?.count ?? 0) > 50 {
                    Text("Die 50 neuesten Aufenthalte werden angezeigt.").font(.caption).foregroundStyle(.secondary)
                }
            }.padding(.top, 12)
        } label: {
            Label("\(response?.stays?.count ?? 0) erkannte Aufenthalte", systemImage: "mappin.and.ellipse").font(.headline)
        }.rjCard()
    }

    private var dayPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            RJSectionTitle(title: "Zeitleiste", subtitle: "Neueste Meldungen zuerst", symbol: "clock")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    dayButton("Alle Tage", date: nil)
                    ForEach(prepared.days) { day in
                        dayButton(day.date.formatted(.dateTime.day().month(.abbreviated)), date: day.date)
                    }
                }
            }
        }
    }
    private func dayButton(_ title: String, date: Date?) -> some View {
        Button { selectedDay = date; timelineLimit = 60 } label: { Text(title).font(.caption.weight(.semibold)).padding(.vertical, 3) }
            .buttonStyle(.bordered).buttonBorderShape(.capsule).tint(selectedDay == date ? .blue : .secondary)
            .accessibilityValue(selectedDay == date ? "Ausgewählt" : "")
    }

    private func timeline(proxy: ScrollViewProxy) -> some View {
        LazyVStack(alignment: .leading, spacing: 14) {
            ForEach(visibleDays) { day in
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text(day.date.formatted(date: .complete, time: .omitted)).font(.subheadline.weight(.semibold))
                        Spacer()
                    }.padding(.bottom, 14)
                    ForEach(day.points) { point in
                        HistoryTimelineRow(point: point, selected: point.id == selectedPoint?.id) {
                            select(point)
                            withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) { proxy.scrollTo("history-map", anchor: .top) }
                        }
                    }
                }.rjCard()
            }
            if timelineLimit < timelineCount {
                Button("Weitere Meldungen (\(timelineCount - timelineLimit))") { timelineLimit += 100 }
                    .buttonStyle(.bordered).frame(maxWidth: .infinity).padding(.vertical, 6)
            }
        }
    }

    private func step(_ direction: Int) {
        playing = false
        selectedIndex = min(max(0, selectedIndex + direction), max(0, points.count - 1))
        focusSelected()
    }
    private func select(_ point: HistoryPoint) {
        playing = false
        if let index = prepared.indexByID[point.id] { selectedIndex = index; focusSelected(); Haptics.impact() }
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
    @MainActor
    private func prepare(preserveSelection: Bool) async {
        let id = UUID(); preparationID = id; preparing = true; playing = false
        let oldPoint = preserveSelection ? selectedPoint : nil
        let input = response?.points ?? []; let networks = enabledNetworks; let calendar = Calendar.current
        let result = await Task.detached(priority: .userInitiated) { HistoryAnalysis.prepare(input, networks: networks, calendar: calendar) }.value
        guard preparationID == id, !Task.isCancelled else { if preparationID == id { preparing = false }; return }
        prepared = result; preparing = false
        if let oldPoint {
            selectedIndex = result.indexByID[oldPoint.id] ?? HistoryAnalysis.nearestIndex(to: Double(oldPoint.timestamp), in: result.points)
        } else { selectedIndex = max(result.points.count - 1, 0); selectedDay = nil; timelineLimit = 60; position = .automatic }
        if let selectedDay, !result.days.contains(where: { $0.date == selectedDay }) { self.selectedDay = nil }
    }
    @MainActor
    private func load(force: Bool = false) async {
        let id = UUID(); loadID = id
        loading = true; error = nil; playing = false
        let requestedDays = days
        defer { if loadID == id { loading = false } }
        do {
            let loaded = try await APIClient.shared.history(tracker: tracker.ref, days: requestedDays, force: force)
            guard !Task.isCancelled, requestedDays == days, loadID == id else { return }
            let preserve = loadedDays == requestedDays && response != nil
            if !preserve { enabledNetworks = Set(loaded.points.map { ($0.network ?? "unknown").rjNormalizedProvider }) }
            loadedDays = requestedDays; response = loaded
            await prepare(preserveSelection: preserve)
        } catch is CancellationError { }
        catch {
            guard !Task.isCancelled, requestedDays == days, loadID == id else { return }
            self.error = error.localizedDescription
        }
    }
}

private struct HistoryTimelineRow: View {
    let point: HistoryPoint
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 0) {
                    Circle().fill((point.network ?? "unknown").rjProviderColor).frame(width: selected ? 12 : 9, height: selected ? 12 : 9)
                        .overlay(Circle().stroke(.white, lineWidth: 1.5)).frame(width: 18, height: 24)
                    Rectangle().fill(Color.secondary.opacity(0.18)).frame(width: 2).frame(maxHeight: .infinity)
                }
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(Date(timeIntervalSince1970: TimeInterval(point.timestamp)).formatted(date: .omitted, time: .standard))
                            .font(.subheadline.weight(.semibold)).monospacedDigit()
                        Spacer()
                        if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(.blue) }
                    }
                    Text(point.address?.bestText ?? String(format: "%.5f, %.5f", point.latitude, point.longitude))
                        .font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                    Text("\((point.network ?? "unknown").rjProviderName) · \(point.accuracyM.flatMap { $0 > 0 ? "±" + $0.metersText : nil } ?? "Genauigkeit unbekannt")")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(.bottom, 18)
            }.foregroundStyle(.primary).padding(.horizontal, 8).padding(.top, 6)
                .background(selected ? Color.blue.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: 14))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct HistoryStayRow: View {
    let stay: JSONValue
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            let address = stay["address"]["label"].stringValue ?? stay["address"]["formatted"].stringValue
            Label(address ?? "Erkannter Aufenthalt", systemImage: "mappin.circle.fill").font(.subheadline.weight(.semibold))
            if let start = stay["start_ts"].numberValue, let end = stay["end_ts"].numberValue {
                Text("\(Date(timeIntervalSince1970: start).rjTimelineText) – \(Date(timeIntervalSince1970: end).formatted(date: .omitted, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("\(stay["duration_text"].stringValue ?? "") · \(stay["report_count"].integer) Meldungen").font(.caption).foregroundStyle(.secondary)
            Divider()
        }
    }
}
