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
    @State private var showStays = true
    @State private var detailMode = 0
    @State private var timelineQuery = ""
    @State private var filteredTimeline: [HistoryDay] = []
    @State private var timelineMatches = 0
    @State private var searchID = UUID()
    @State private var fullscreen = false
    @State private var followSelection = true

    private var points: [HistoryPoint] { prepared.points }
    private var selectedPoint: HistoryPoint? {
        guard !points.isEmpty else { return nil }
        return points[min(max(selectedIndex, 0), points.count - 1)]
    }
    private var networks: [String] {
        Array(Set((response?.points ?? []).map { ($0.network ?? "unknown").rjNormalizedProvider })).sorted()
    }
    private var visibleDays: [HistoryDay] {
        var remaining = timelineLimit
        return filteredTimeline.compactMap { day in
            guard remaining > 0 else { return nil }
            let visible = Array(day.points.prefix(remaining)); remaining -= visible.count
            return HistoryDay(date: day.date, points: visible)
        }
    }
    private var timelineCount: Int { timelineMatches }

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
                        if !prepared.availableDays.isEmpty { dayPicker }
                        if points.isEmpty {
                            ContentUnavailableView("Keine Standortpunkte", systemImage: "clock", description: Text("Für diesen Zeitraum und diese Netzwerkauswahl liegen keine Meldungen vor."))
                        } else {
                            metrics
                            historyMap.id("history-map")
                            playback
                            if let total = response?.matchingTotal, total > (response?.points.count ?? 0) {
                                Label("Die neuesten \(response?.points.count ?? 0) von \(total) Meldungen sind geladen. Karte und Export enthalten diesen Ausschnitt.", systemImage: "info.circle")
                                    .font(.caption).foregroundStyle(.orange)
                            }
                            Picker("Verlaufansicht", selection: $detailMode) {
                                Text("Meldungen").tag(0); Text("Übersicht").tag(1); Text("Aufenthalte").tag(2)
                            }.pickerStyle(.segmented)
                            if detailMode == 0 {
                                searchField
                                timeline(proxy: proxy)
                            } else if detailMode == 1 {
                                overview
                                summary
                            } else if !(response?.stays ?? []).isEmpty { staysCard }
                            else {
                                ContentUnavailableView("Keine Aufenthalte erkannt", systemImage: "mappin.and.ellipse", description: Text("Die Serverauswertung enthält für den geladenen Zeitraum keine Aufenthalte."))
                            }
                        }
                    }
                }.padding(16).frame(maxWidth: 850).frame(maxWidth: .infinity)
            }
        }
        .rjScreenChrome()
        .navigationTitle("Standortverlauf").navigationBarTitleDisplayMode(.inline)
        .task(id: days) { await load() }
        .onAppear { expandInspector() }
        .task(id: timelineQuery) { await filterTimeline() }
        .sheet(isPresented: $fullscreen) {
            NavigationStack {
                VStack(spacing: 8) {
                    HistoryRouteMap(prepared: prepared, selected: selectedPoint, position: $position, onSelect: select)
                    ScrollView { playback.padding(12) }.frame(maxHeight: 310)
                }
                .navigationTitle("Verlaufkarte").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { fullscreen = false } } }
                .rjScreenChrome()
            }.presentationDetents([.large])
        }
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
                Button("Auswahl als CSV exportieren", systemImage: "tablecells") { beginExport(gpx: false) }
                Button("Auswahl als GPX exportieren", systemImage: "point.topleft.down.to.point.bottomright.curvepath") { beginExport(gpx: true) }
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
            Text("Orte, Zeitpunkte und Quellen auf einen Blick.").font(.subheadline).foregroundStyle(.secondary)
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
        HistoryRouteMap(prepared: prepared, selected: selectedPoint, position: $position, onSelect: select)
        .frame(height: 340).clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 8) {
                Button { playing = false; position = .automatic } label: { Image(systemName: "scope").rjGlassControl() }
                    .accessibilityLabel("Gesamte Auswahl auf Karte zeigen")
                Button { fullscreen = true } label: { Image(systemName: "arrow.up.left.and.arrow.down.right").rjGlassControl() }
                    .accessibilityLabel("Karte groß öffnen")
            }.buttonStyle(.plain).padding(12)
        }
        .overlay(alignment: .bottomLeading) {
            Label(selectedDay?.formatted(.dateTime.day().month(.abbreviated)) ?? "Alle Tage", systemImage: "calendar")
                .font(.caption.weight(.semibold)).padding(.horizontal, 12).padding(.vertical, 8)
                .rjGlass(in: Capsule()).padding(12)
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
                        selectedIndex = HistoryAnalysis.nearestIndex(to: value, in: points)
                    }), in: Double(first.timestamp)...Double(last.timestamp)) { editing in
                        if editing { playing = false } else { focusSelected() }
                    }
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
                HStack {
                    Toggle("Karte folgt Auswahl", isOn: $followSelection).font(.caption)
                    Button("Neueste") { step(points.count) }.font(.caption.weight(.semibold)).disabled(selectedIndex == points.count - 1)
                }
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
                Text("Aufenthalte sind eine Serverauswertung für den gesamten geladenen Zeitraum, über alle Netze. Tages- und Quellenfilter gelten für die Meldungen und die Karte. Aufenthalte sind aus Meldungen abgeleitet.")
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
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(selectedDay?.formatted(date: .complete, time: .omitted) ?? "Gesamter Zeitraum").font(.subheadline.weight(.semibold))
                Spacer()
                if selectedDay != nil { Button("Alle Tage") { chooseDay(nil) }.font(.caption.bold()) }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    dayButton("Alle", detail: "\(prepared.availableDays.count) Tage", date: nil)
                    ForEach(prepared.availableDays) { day in
                        dayButton(day.date.formatted(.dateTime.day().month(.abbreviated)), detail: "\(day.points.count) Meldungen", date: day.date)
                    }
                }
            }
        }
    }
    private func dayButton(_ title: String, detail: String, date: Date?) -> some View {
        Button { chooseDay(date) } label: {
            VStack(spacing: 5) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption2)
            }.padding(.horizontal, 14).padding(.vertical, 12)
                .foregroundStyle(selectedDay == date ? Color.white : Color.primary)
                .background(selectedDay == date ? Color.blue : Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))
        }.buttonStyle(.plain).disabled(preparing || loading)
            .accessibilityValue(selectedDay == date ? "Ausgewählt" : "")
    }
    private func chooseDay(_ date: Date?) {
        selectedDay = date; timelineLimit = 60; playing = false
        Task { await prepare(preserveSelection: true); position = .automatic }
    }

    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Ort, Quelle oder Uhrzeit suchen", text: $timelineQuery).autocorrectionDisabled()
            if !timelineQuery.isEmpty {
                Button { timelineQuery = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .accessibilityLabel("Suche löschen")
            }
        }.padding(14).background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
    }

    private var metrics: some View {
        HStack(spacing: 10) {
            metric("Meldungen", value: "\(points.count)", symbol: "location.fill", color: .blue)
            metric("Quellen", value: "\(prepared.sourceCounts.count)", symbol: "antenna.radiowaves.left.and.right", color: .purple)
            metric("Genauigkeit¹", value: prepared.medianAccuracy.map { "±" + $0.metersText } ?? "–", symbol: "scope", color: .teal)
        }
    }
    private func metric(_ title: String, value: String, symbol: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol).font(.subheadline).foregroundStyle(color)
            Text(value).font(.title3.bold()).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            Text(title).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
            .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
    }
    private var overview: some View {
        VStack(alignment: .leading, spacing: 16) {
            RJSectionTitle(title: "Zeit & Datenqualität", subtitle: "Für die ausgewählten Tage und Quellen", symbol: "chart.bar.xaxis")
            if let first = points.first, let last = points.last {
                overviewRow("Erste Meldung", value: Date(timeIntervalSince1970: TimeInterval(first.timestamp)).rjTimelineText, symbol: "flag")
                overviewRow("Letzte Meldung", value: Date(timeIntervalSince1970: TimeInterval(last.timestamp)).rjTimelineText, symbol: "flag.checkered")
                overviewRow("Größte Meldungslücke", value: duration(prepared.longestGap), symbol: "clock.badge.questionmark")
            }
            Divider()
            ForEach(prepared.sourceCounts.keys.sorted(), id: \.self) { network in
                HStack {
                    ProviderBadge(provider: network)
                    Spacer()
                    Text("\(prepared.sourceCounts[network] ?? 0) Meldungen").font(.subheadline).monospacedDigit()
                }
            }
            Text("¹ Median der gemeldeten Genauigkeit. Eine Meldungslücke bedeutet, dass keine Standortdaten vorliegen. Linien sind Verbindungen zwischen Messpunkten und keine aufgezeichnete Reiseroute.")
                .font(.caption).foregroundStyle(.secondary)
        }.rjCard()
    }
    private func overviewRow(_ title: String, value: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(.blue).frame(width: 22)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.subheadline.weight(.medium)).monospacedDigit()
            }
        }
    }
    private func duration(_ seconds: TimeInterval) -> String {
        if seconds < 60 { return "\(Int(seconds)) Sek." }
        if seconds < 3600 { return "\(Int(seconds / 60)) Min." }
        if seconds < 86400 { return "\(Int(seconds / 3600)) Std. \(Int(seconds.truncatingRemainder(dividingBy: 3600) / 60)) Min." }
        return "\(Int(seconds / 86400)) Tage \(Int(seconds.truncatingRemainder(dividingBy: 86400) / 3600)) Std."
    }

    private func timeline(proxy: ScrollViewProxy) -> some View {
        LazyVStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("\(timelineCount) Meldungen").font(.headline)
                Spacer()
                Text("Neueste zuerst").font(.caption).foregroundStyle(.secondary)
            }
            if filteredTimeline.isEmpty {
                ContentUnavailableView.search(text: timelineQuery)
            }
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
        guard followSelection, let point = selectedPoint else { return }
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
        if !preserveSelection { selectedDay = nil }
        let day = selectedDay
        let work = Task.detached(priority: .userInitiated) { HistoryAnalysis.prepare(input, networks: networks, calendar: calendar, day: day) }
        let result = await withTaskCancellationHandler { await work.value } onCancel: { work.cancel() }
        guard preparationID == id, !Task.isCancelled else { if preparationID == id { preparing = false }; return }
        prepared = result; preparing = false
        if let oldPoint {
            selectedIndex = result.indexByID[oldPoint.id] ?? HistoryAnalysis.nearestIndex(to: Double(oldPoint.timestamp), in: result.points)
        } else { selectedIndex = max(result.points.count - 1, 0); timelineLimit = 60; position = .automatic }
        if let selectedDay, !result.availableDays.contains(where: { $0.date == selectedDay }) { self.selectedDay = nil }
        await filterTimeline()
    }
    @MainActor private func filterTimeline() async {
        let id = UUID(); searchID = id
        let days = prepared.days; let query = timelineQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let result = await Task.detached(priority: .userInitiated) {
            days.compactMap { day -> HistoryDay? in
                let points = query.isEmpty ? day.points : day.points.filter { point in
                    let time = Date(timeIntervalSince1970: TimeInterval(point.timestamp)).formatted(date: .abbreviated, time: .standard)
                    let searchable = "\(point.address?.bestText ?? "") \((point.network ?? "unknown").rjProviderName) \(time) \(point.latitude) \(point.longitude)"
                    return searchable.localizedStandardContains(query)
                }
                return points.isEmpty ? nil : HistoryDay(date: day.date, points: points)
            }
        }.value
        guard searchID == id, !Task.isCancelled else { return }
        filteredTimeline = result; timelineMatches = result.reduce(0) { $0 + $1.points.count }; timelineLimit = 60
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
                        .font(.subheadline.weight(.medium)).foregroundStyle(.primary).lineLimit(2)
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


private struct HistoryRouteMap: View {
    let prepared: PreparedHistory
    let selected: HistoryPoint?
    @Binding var position: MapCameraPosition
    let onSelect: (HistoryPoint) -> Void
    var body: some View {
        Map(position: $position) {
            ForEach(prepared.mapSegments) { segment in
                if segment.points.count > 1 {
                    MapPolyline(coordinates: segment.coordinates)
                        .stroke((segment.points.first?.network ?? "unknown").rjProviderColor.opacity(0.75), lineWidth: 3)
                }
            }
            ForEach(prepared.mapPoints) { point in
                Annotation("", coordinate: point.coordinate) {
                    Button { onSelect(point) } label: {
                        Circle().fill((point.network ?? "unknown").rjProviderColor)
                            .frame(width: 8, height: 8).overlay(Circle().stroke(.white, lineWidth: 1.5))
                            .frame(width: 32, height: 32).contentShape(Circle())
                    }.buttonStyle(.plain)
                        .accessibilityLabel("Meldung \(Date(timeIntervalSince1970: TimeInterval(point.timestamp)).rjTimelineText)")
                }
            }
            if let first = prepared.points.first { Marker("Beginn", systemImage: "flag", coordinate: first.coordinate).tint(.green) }
            if let last = prepared.points.last { Marker("Letzte Meldung", systemImage: "flag.checkered", coordinate: last.coordinate).tint(.orange) }
            if let point = selected {
                if let accuracy = point.accuracyM, accuracy > 0 {
                    MapCircle(center: point.coordinate, radius: min(accuracy, 100_000)).foregroundStyle(.blue.opacity(0.1))
                        .stroke(.blue.opacity(0.25), lineWidth: 1)
                }
                Annotation("", coordinate: point.coordinate) {
                    Circle().fill(.blue).frame(width: 18, height: 18)
                        .overlay(Circle().stroke(.white, lineWidth: 3)).shadow(color: .blue.opacity(0.4), radius: 8)
                }
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .mapControls { MapCompass(); MapScaleView() }
    }
}
