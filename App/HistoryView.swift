import SwiftUI
import MapKit
import UniformTypeIdentifiers

struct HistoryView: View {
    let tracker: Tracker
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.rjExpandInspector) private var expandInspector
    @AppStorage("historyPeriodDays") private var days = 1
    @AppStorage("historyEveryReport") private var detailed = false
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
        @State private var detailMode = 0
    @State private var timelineQuery = ""
    @State private var filteredTimeline: [HistoryDay] = []
    @State private var timelineMatches = 0
    @State private var searchID = UUID()
    @State private var fullscreen = false
    @State private var followSelection = true
    @State private var followLatest = true
    @State private var networks: [String] = []
    @State private var streamCursor: String?
    @State private var streamSupported = true
    @State private var receiving = false
    @State private var caughtUp = false
    @State private var reportIDs: Set<String> = []
    @State private var liveError: String?
    @State private var lastLiveSync: Date?

    private var points: [HistoryPoint] { prepared.displayPoints }
    private var selectedPoint: HistoryPoint? {
        guard !points.isEmpty else { return nil }
        return points[min(max(selectedIndex, 0), points.count - 1)]
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
                    liveStatus
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
                        Picker("Detailgrad", selection: $detailed) {
                            Text("Übersichtlich").tag(false); Text("Jeder Report").tag(true)
                        }.pickerStyle(.segmented)
                        Text(detailed ? "Alle empfangenen Reports, auch am selben Ort und zur selben Sekunde. Dichte Kartenpunkte werden beim Zoomen aufgefächert." : "Nahe Meldungen werden für die Ansicht gebündelt. Alle Originalreports bleiben gespeichert und lassen sich einzeln anzeigen.")
                            .font(.caption).foregroundStyle(.secondary)
                        if !prepared.availableDays.isEmpty { dayPicker }
                        if points.isEmpty {
                            ContentUnavailableView("Keine Standortpunkte", systemImage: "clock", description: Text("Für diesen Zeitraum und diese Netzwerkauswahl liegen keine Meldungen vor."))
                        } else {
                            metrics
                            historyMap.id("history-map")
                            playback
                            if let total = response?.matchingTotal, total > (response?.points.count ?? 0) {
                                Label("\(response?.points.count ?? 0) von \(total) Reports geladen. Weitere werden automatisch nachgeladen; der Export enthält die bisher geladenen Originalreports.", systemImage: "info.circle")
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
                            } else if !visibleStays.isEmpty { staysCard }
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
        .task(id: "\(days)-\(scenePhase)") {
            if scenePhase == .active { await watchHistory() }
        }
        .onChange(of: detailed) { _, _ in Task { await prepare(preserveSelection: true) } }
        .onAppear { expandInspector() }
        .task(id: timelineQuery) {
            do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
            await filterTimeline()
        }
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
        .refreshable {
            streamCursor = nil; caughtUp = false
            await load(force: true)
            await receiveReports()
        }
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
                        followLatest = false
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
                    Button("Neueste") { step(points.count); followLatest = true }.font(.caption.weight(.semibold)).disabled(selectedIndex == points.count - 1 && followLatest)
                }
                Divider()
                ResolvedAddressText(location: point.rjTrackerLocation, fallback: String(format: "%.5f, %.5f", point.latitude, point.longitude)).font(.subheadline)
                HStack {
                    AccuracyPill(accuracy: point.accuracyM)
                    Spacer()
                    Text("\(selectedIndex + 1) / \(points.count) \(detailed ? "Reports" : "Stationen")").font(.caption).monospacedDigit().foregroundStyle(.secondary)
                }
            }
        }.rjCard()
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 12) {
            RJSectionTitle(title: "Dein Verlauf", subtitle: "\(prepared.points.count) Originalreports · \(points.count) angezeigte \(detailed ? "Reports" : "Stationen")", symbol: "chart.xyaxis.line")
            if let total = response?.matchingTotal, total > (response?.points.count ?? 0) {
                Label("Die neuesten \(response?.points.count ?? 0) von \(total) Meldungen sind geladen. Der Export enthält diesen Ausschnitt.", systemImage: "info.circle")
                    .font(.footnote).foregroundStyle(.orange)
            }
            Text("Farben zeigen das Ortungsnetz. Linien verbinden Meldungen derselben Quelle. Lücken und unplausible Sprünge bleiben unterbrochen.")
                .font(.footnote).foregroundStyle(.secondary)
        }.rjCard()
    }

    private var visibleStays: [JSONValue] {
        (response?.stays ?? []).filter { stay in
            if let selectedDay {
                let start = stay["start_ts"].numberValue ?? 0
                let end = stay["end_ts"].numberValue ?? start
                let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: selectedDay) ?? selectedDay.addingTimeInterval(86400)
                if end < selectedDay.timeIntervalSince1970 || start >= tomorrow.timeIntervalSince1970 { return false }
            }
            let sources = Set((stay["networks"].objectValue ?? [:]).keys.map { $0.rjNormalizedProvider })
            return sources.isEmpty || !sources.isDisjoint(with: enabledNetworks)
        }
    }
    private var staysCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            RJSectionTitle(title: "Aufenthaltsorte", subtitle: "\(visibleStays.count) aus Meldungen abgeleitete Aufenthalte", symbol: "mappin.and.ellipse")
            Text("Ort antippen, um ihn auf der Karte zu sehen. Dauer und Genauigkeit beziehen sich auf empfangene Meldungen.").font(.caption).foregroundStyle(.secondary)
            ForEach(Array(visibleStays.prefix(100).enumerated()), id: \.offset) { _, stay in
                Button {
                    playing = false; followLatest = false
                    if let timestamp = stay["start_ts"].numberValue { selectedIndex = HistoryAnalysis.nearestIndex(to: timestamp, in: points) }
                    if let latitude = stay["latitude"].numberValue, let longitude = stay["longitude"].numberValue {
                        let zoom = max(700, (stay["radius_m"].numberValue ?? 100) * 5)
                        position = .region(.init(center: .init(latitude: latitude, longitude: longitude), latitudinalMeters: zoom, longitudinalMeters: zoom))
                    }
                    fullscreen = true
                } label: { HistoryStayRow(stay: stay) }.buttonStyle(.plain)
            }
            if visibleStays.count > 100 { Text("Die 100 neuesten Aufenthalte werden angezeigt.").font(.caption).foregroundStyle(.secondary) }
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
            metric("Originalreports", value: "\(prepared.points.count)", symbol: "location.fill", color: .blue)
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
                Text("\(timelineCount) \(detailed ? "Reports" : "Stationen")").font(.headline)
                Spacer()
                Text("Neueste zuerst").font(.caption).foregroundStyle(.secondary)
            }
            if filteredTimeline.isEmpty {
                ContentUnavailableView.search(text: timelineQuery)
            }
            ForEach(visibleDays) { day in
                LazyVStack(alignment: .leading, spacing: 0) {
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
                    .onAppear { timelineLimit = min(timelineCount, timelineLimit + 100) }
            }
        }
    }

    private func step(_ direction: Int) {
        playing = false; followLatest = false
        selectedIndex = min(max(0, selectedIndex + direction), max(0, points.count - 1))
        focusSelected()
    }
    private func select(_ point: HistoryPoint) {
        playing = false; followLatest = false
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
        document = HistoryExportDocument(text: gpx ? HistoryAnalysis.gpx(prepared.points) : HistoryAnalysis.csv(prepared.points))
        export = true
    }
    @MainActor
    private func prepare(preserveSelection: Bool, stopPlayback: Bool = true) async {
        let id = UUID(); preparationID = id; preparing = true
        if stopPlayback { playing = false }
        let oldPoint = preserveSelection ? selectedPoint : nil
        let wasAtLatest = followLatest && selectedIndex >= points.count - 1
        let input = response?.points ?? []; let networks = enabledNetworks; let calendar = Calendar.current
        if !preserveSelection { selectedDay = nil }
        let day = selectedDay; let detailed = detailed
        let work = Task.detached(priority: .userInitiated) { HistoryAnalysis.prepare(input, networks: networks, calendar: calendar, day: day, detailed: detailed) }
        let result = await withTaskCancellationHandler { await work.value } onCancel: { work.cancel() }
        guard preparationID == id, !Task.isCancelled else { if preparationID == id { preparing = false }; return }
        prepared = result; preparing = false
        if wasAtLatest { selectedIndex = max(result.displayPoints.count - 1, 0) }
        else if let oldPoint {
            selectedIndex = result.indexByID[oldPoint.id] ?? HistoryAnalysis.nearestIndex(to: Double(oldPoint.timestamp), in: result.displayPoints)
        } else { selectedIndex = max(result.displayPoints.count - 1, 0); timelineLimit = 60; position = .automatic }
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
        filteredTimeline = result; timelineMatches = result.reduce(0) { $0 + $1.points.count }
    }
    private var liveStatus: some View {
        HStack(alignment: .top, spacing: 8) {
            if receiving { ProgressView().controlSize(.mini) }
            else { Image(systemName: liveError == nil ? "dot.radiowaves.left.and.right" : "wifi.exclamationmark").foregroundStyle(liveError == nil ? Color.green : Color.orange) }
            VStack(alignment: .leading, spacing: 3) {
                Text(receiving && !caughtUp ? "Alle Reports werden nachgeladen …" : "Live-Verlauf").font(.caption.weight(.semibold))
                if !streamSupported { Text("Für alle Einzelreports bitte Backend 20.1 aktualisieren.").font(.caption).foregroundStyle(.orange) }
                else if let liveError { Text(liveError).font(.caption).foregroundStyle(.orange) }
                else if let lastLiveSync { Text("Synchronisiert \(lastLiveSync.formatted(date: .omitted, time: .standard)) · Prüfung alle 5 Sekunden").font(.caption2).foregroundStyle(.secondary) }
            }
            Spacer()
        }.padding(.horizontal, 4)
    }
    @MainActor private func watchHistory() async {
        if loadedDays != days {
            streamCursor = nil; caughtUp = false; reportIDs = []; followLatest = true
        }
        await load(force: response != nil)
        guard !Task.isCancelled else { return }
        await receiveReports()
        var cycle = 0
        while !Task.isCancelled {
            do { try await Task.sleep(for: .seconds(5)) } catch { return }
            guard scenePhase == .active else { return }
            await receiveReports()
            cycle += 1
            if cycle.isMultiple(of: 4) { await load(force: true) }
        }
    }
    @MainActor private func receiveReports() async {
        guard !receiving, streamSupported else { return }
        receiving = true; defer { receiving = false }
        let requestedDays = days
        do {
            var more = true
            while more, !Task.isCancelled {
                let page = try await APIClient.shared.historyStream(tracker: tracker.ref, days: requestedDays, cursor: streamCursor, replay: caughtUp)
                guard requestedDays == days, !Task.isCancelled else { return }
                let previousCount = response?.points.count ?? 0
                if response == nil { response = HistoryResponse(status: "ok", tracker: tracker, points: []) }
                var merged = Dictionary(uniqueKeysWithValues: (response?.points ?? []).map { ($0.id, $0) })
                var changed = false
                for point in page.points {
                    if merged[point.id] != point { changed = true; merged[point.id] = point }
                }
                let cutoff = Int(Date().timeIntervalSince1970) - requestedDays * 86400
                response?.points = merged.values.filter { $0.timestamp >= cutoff }
                reportIDs = Set((response?.points ?? []).map(\.id))
                response?.matchingTotal = page.matchingTotal
                let discovered = Set(page.points.map { ($0.network ?? "unknown").rjNormalizedProvider })
                enabledNetworks.formUnion(discovered.subtracting(Set(networks)))
                networks = Array(Set(networks).union(discovered)).sorted()
                streamCursor = page.nextCursor
                more = page.hasMore
                caughtUp = !more
                if changed || response?.points.count != previousCount {
                    await prepare(preserveSelection: true, stopPlayback: false)
                }
                lastLiveSync = Date(); liveError = nil
                if more { await Task.yield() }
            }
        } catch is CancellationError { }
        catch APIError.http(let status, _) where status == 404 {
            streamSupported = false; liveError = nil
        } catch {
            if requestedDays == days, !Task.isCancelled { liveError = "Aktualisierung fehlgeschlagen. Gespeicherter Stand bleibt sichtbar." }
        }
    }
    @MainActor private func load(force: Bool = false) async {
        let id = UUID(); loadID = id
        loading = response == nil; error = nil
        let requestedDays = days
        defer { if loadID == id { loading = false } }
        do {
            var loaded = try await APIClient.shared.history(tracker: tracker.ref, days: requestedDays, force: force)
            guard !Task.isCancelled, requestedDays == days, loadID == id else { return }
            let preserve = loadedDays == requestedDays && response != nil
            let originalIDs = reportIDs
            if preserve {
                let cutoff = Int(Date().timeIntervalSince1970) - requestedDays * 86400
                var merged = Dictionary(uniqueKeysWithValues: (response?.points ?? []).map { ($0.id, $0) })
                for point in loaded.points {
                    if var existing = merged[point.id] {
                        if let address = point.address { existing.address = address; merged[point.id] = existing }
                    } else { merged[point.id] = point }
                }
                loaded.points = merged.values.filter { $0.timestamp >= cutoff }
            } else {
                enabledNetworks = Set(loaded.points.map { ($0.network ?? "unknown").rjNormalizedProvider })
                timelineLimit = 60
            }
            let discovered = Set(loaded.points.map { ($0.network ?? "unknown").rjNormalizedProvider })
            enabledNetworks.formUnion(discovered.subtracting(Set(networks)))
            networks = Array(discovered).sorted()
            reportIDs = Set(loaded.points.map(\.id))
            loadedDays = requestedDays; response = loaded
            if !preserve || originalIDs != reportIDs { await prepare(preserveSelection: preserve, stopPlayback: !preserve) }
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
                    if let reportID = point.reportID {
                        Text("Report " + String(reportID.prefix(10))).font(.system(.caption2, design: .monospaced)).foregroundStyle(.tertiary)
                    }
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
            let latitude = stay["latitude"].numberValue ?? 0
            let longitude = stay["longitude"].numberValue ?? 0
            HStack(alignment: .top) {
                Label(address ?? String(format: "%.5f, %.5f", latitude, longitude), systemImage: "mappin.circle.fill").font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                Spacer()
                Text(stay["duration_text"].stringValue ?? "").font(.subheadline.bold()).foregroundStyle(.blue)
            }
            if let start = stay["start_ts"].numberValue, let end = stay["end_ts"].numberValue {
                Text("\(Date(timeIntervalSince1970: start).rjTimelineText) – \(Date(timeIntervalSince1970: end).formatted(date: .omitted, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Text("\(stay["report_count"].integer) Reports").font(.caption).foregroundStyle(.secondary)
                if let accuracy = stay["median_accuracy_m"].numberValue, accuracy > 0 { AccuracyPill(accuracy: accuracy) }
                Spacer()
                Image(systemName: "map").foregroundStyle(.blue)
            }
            Divider()
        }
    }
}

