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
    @AppStorage("historySatellite") private var satellite = false
    @State private var response: HistoryResponse?
    @State private var loadedDays: Int?
    @State private var calendarResponse: HistoryCalendarResponse?
    @State private var selectedDates: Set<String> = []
    @State private var draftDates: Set<String> = []
    @State private var showCalendar = false
    @State private var dateSearch = ""
    @State private var loadedScope = ""
    @State private var selectionMode = "today"
    private var historyCalendar: Calendar { HistoryCalendar.calendar(timezone: calendarResponse?.timezone ?? TimeZone.current.identifier) }
    private var todayKey: String { HistoryCalendar.key(Date(), calendar: historyCalendar) }
    private var yesterdayKey: String {
        HistoryCalendar.key(historyCalendar.date(byAdding: .day, value: -1, to: Date()) ?? Date(), calendar: historyCalendar)
    }
    private var requestDates: [String] {
        if selectionMode == "today" { return [todayKey] }
        return selectedDates.isEmpty ? [todayKey] : selectedDates.sorted()
    }
    private var dateScope: String { requestDates.joined(separator: ",") }
    private var matchingStoredDays: [StoredHistoryDay] {
        (calendarResponse?.days ?? []).filter { dateSearch.isEmpty || $0.date.contains(dateSearch) || dayTitle($0.date).localizedCaseInsensitiveContains(dateSearch) }
    }
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
                VStack(spacing: 16) {
                    periodPicker
                    if loading || preparing {
                        HStack(spacing: 10) {
                            ProgressView().controlSize(.small)
                            Text(response == nil ? "Verlauf wird geladen …" : "Verlauf wird aktualisiert …").font(.subheadline).foregroundStyle(.secondary)
                            Spacer()
                        }.padding(.horizontal, 4).accessibilityIdentifier("history-loading")
                    }
                    if let error {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Verlauf konnte nicht aktualisiert werden", systemImage: "wifi.exclamationmark").font(.headline)
                            Text(error).font(.footnote).foregroundStyle(.secondary)
                            Button("Erneut versuchen") { Task { await load(force: true) } }.buttonStyle(.bordered).buttonBorderShape(.capsule)
                        }.rjCard()
                    }
                    if response != nil {
                        if loadedDays != nil, loadedScope != dateScope {
                            Label("Angezeigt: letzter erfolgreich geladener Zeitraum.", systemImage: "clock.badge.exclamationmark")
                                .font(.footnote).foregroundStyle(.orange).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if points.isEmpty {
                            VStack(spacing: 14) {
                                ContentUnavailableView("Keine Standorte", systemImage: "point.topleft.down.to.point.bottomright.curvepath",
                                                       description: Text("Für diesen Zeitraum und diese Netzwerke liegen keine Meldungen vor. Wähle einen anderen Tag."))
                                if networks.count > 1 { sourceFilters }
                            }.rjCard()
                        } else {
                            historyMap.id("history-map")
                            playback
                            metrics
                            if networks.count > 1 { sourceFilters }
                            if let total = response?.matchingTotal, total > (response?.points.count ?? 0) {
                                Label("\(response?.points.count ?? 0) von \(total) Reports geladen. Weitere werden automatisch nachgeladen; der Export enthält die bisher geladenen Originalreports.", systemImage: "info.circle")
                                    .font(.caption).foregroundStyle(.orange)
                            }
                            Picker("Verlaufansicht", selection: $detailMode) {
                                Text("Zeitleiste").tag(0); Text("Aufenthalte").tag(2); Text("Analyse").tag(1)
                            }.pickerStyle(.segmented)
                            if detailMode == 0 {
                                searchField
                                timeline(proxy: proxy)
                            } else if detailMode == 1 {
                                overview
                            } else if !visibleStays.isEmpty { staysCard }
                            else {
                                ContentUnavailableView("Keine Aufenthalte erkannt", systemImage: "mappin.and.ellipse", description: Text("Die Serverauswertung enthält für den geladenen Zeitraum keine Aufenthalte.")).rjCard()
                            }
                        }
                    }
                    liveStatus
                }.padding(16).padding(.bottom, 24).frame(maxWidth: 850).frame(maxWidth: .infinity)
            }
        }
        .rjScreenChrome()
        .navigationTitle("Standortverlauf").navigationBarTitleDisplayMode(.inline)
        .task(id: "\(dateScope)-\(scenePhase)") {
            if scenePhase == .active { await watchHistory() }
        }
        .onChange(of: detailed) { _, _ in Task { await prepare(preserveSelection: true) } }
        .onAppear { expandInspector() }
        .task(id: timelineQuery) {
            do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
            await filterTimeline()
        }
        .sheet(isPresented: $showCalendar) { calendarSheet }
        .fullScreenCover(isPresented: $fullscreen) { fullscreenMap }
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
        .sensoryFeedback(.selection, trigger: selectedIndex) { _, _ in !playing }
        .toolbar {
            Menu {
                Picker("Detailgrad", selection: $detailed) {
                    Label("Übersichtlich", systemImage: "circle.grid.2x1").tag(false)
                    Label("Jeder Report", systemImage: "circle.grid.3x3.fill").tag(true)
                }
                Toggle(isOn: $satellite) { Label("Satellit", systemImage: "globe.europe.africa") }
                Divider()
                Button("Auswahl als CSV exportieren", systemImage: "tablecells") { beginExport(gpx: false) }
                    .disabled(points.isEmpty || loading || preparing)
                Button("Auswahl als GPX exportieren", systemImage: "point.topleft.down.to.point.bottomright.curvepath") { beginExport(gpx: true) }
                    .disabled(points.isEmpty || loading || preparing)
            } label: { Image(systemName: "ellipsis") }
                .accessibilityLabel("Verlaufsoptionen und Export")
        }
        .fileExporter(isPresented: $export, document: document, contentType: exportGPX ? .rjGPX : .commaSeparatedText,
                      defaultFilename: exportGPX ? "RJ-Tracker-Verlauf.gpx" : "RJ-Tracker-Verlauf.csv") { result in
            if case .failure(let failure) = result { error = failure.localizedDescription }
        }
    }

    // MARK: Period

    private var periodTitle: String {
        if selectionMode == "today" { return "Heute" }
        if requestDates == [yesterdayKey] { return "Gestern" }
        if requestDates.count == 1, let key = requestDates.first { return dayTitle(key) }
        return "\(requestDates.count) Tage"
    }

    private var periodSubtitle: String {
        if selectionMode == "today" { return tracker.name + " · ab 00:00 Uhr" }
        guard requestDates.count > 1, let first = requestDates.first, let last = requestDates.last else { return tracker.name + " · ganzer Tag" }
        return tracker.name + " · " + dayShort(first) + " – " + dayShort(last)
    }

    /// Recent days as a calendar strip, with the number of stored reports per day.
    private var stripKeys: [String] {
        var keys = (0..<14).compactMap { offset in
            historyCalendar.date(byAdding: .day, value: -offset, to: Date()).map { HistoryCalendar.key($0, calendar: historyCalendar) }
        }
        for key in requestDates where !keys.contains(key) { keys.append(key) }
        return keys.sorted()
    }
    private var storedCounts: [String: Int] {
        Dictionary((calendarResponse?.days ?? []).map { ($0.date, $0.count) }, uniquingKeysWith: { first, _ in first })
    }

    private var periodPicker: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(periodTitle).font(.largeTitle.bold()).contentTransition(.opacity)
                    Text(periodSubtitle)
                        .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Menu {
                    Button("Letzte 7 Tage", systemImage: "7.circle") { chooseRange(7) }
                    Button("Letzte 14 Tage", systemImage: "14.circle") { chooseRange(14) }
                    Button("Letzte 30 Tage", systemImage: "30.circle") { chooseRange(30) }
                    Button("Letzte 90 Tage", systemImage: "calendar.badge.clock") { chooseRange(90) }
                    Divider()
                    Button("Tage frei auswählen …", systemImage: "calendar") { draftDates = Set(requestDates); showCalendar = true }
                } label: {
                    Image(systemName: "calendar").font(.title3.weight(.medium)).rjGlassControl()
                }.buttonStyle(.plain).accessibilityLabel("Zeitraum wählen")
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(stripKeys, id: \.self) { key in dayChip(key) }
                }.padding(.vertical, 2)
            }
            .defaultScrollAnchor(.trailing)
            if calendarResponse == nil {
                Text("Kalender wird geladen. Für die Tagesauswahl Backend 20.2 oder neuer verwenden.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func dayChip(_ key: String) -> some View {
        let selected = requestDates.contains(key)
        let date = HistoryCalendar.date(key, calendar: historyCalendar)
        let count = storedCounts[key] ?? 0
        return Button { chooseSingleDay(key) } label: {
            VStack(spacing: 4) {
                Text(key == todayKey ? "Heute" : (date.map { weekday($0) } ?? ""))
                    .font(.caption2.weight(.semibold)).textCase(.uppercase)
                    .foregroundStyle(selected ? Color.white.opacity(0.85) : .secondary)
                Text(date.map { String(historyCalendar.component(.day, from: $0)) } ?? key)
                    .font(.title3.weight(.semibold)).monospacedDigit()
                    .foregroundStyle(selected ? Color.white : .primary)
                Circle().fill(count > 0 ? (selected ? Color.white : Color.accentColor) : Color.clear)
                    .frame(width: 5, height: 5)
            }
            .frame(width: 54, height: 72)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(selected ? AnyShapeStyle(Color.accentColor.gradient) : AnyShapeStyle(Color(uiColor: .secondarySystemGroupedBackground)))
            }
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.primary.opacity(selected ? 0 : 0.05), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(dayTitle(key) + (count > 0 ? ", \(count) Meldungen" : ", keine Meldungen"))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func chooseSingleDay(_ key: String) {
        selectedDay = nil
        if key == todayKey { selectionMode = "today"; selectedDates = [todayKey] }
        else { selectionMode = "custom"; selectedDates = [key] }
    }
    private func chooseRange(_ count: Int) {
        days = count; selectionMode = "custom"; selectedDay = nil
        selectedDates = HistoryCalendar.range(days: count, now: Date(), calendar: historyCalendar)
    }
    private func weekday(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE"); formatter.timeZone = historyCalendar.timeZone
        formatter.dateFormat = "EE"
        return formatter.string(from: date).replacingOccurrences(of: ".", with: "")
    }
    private func dayShort(_ key: String) -> String {
        guard let date = HistoryCalendar.date(key, calendar: historyCalendar) else { return key }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE"); formatter.timeZone = historyCalendar.timeZone
        formatter.dateFormat = "d. MMM"
        return formatter.string(from: date)
    }

    private func dayTitle(_ key: String) -> String {
        guard let date = HistoryCalendar.date(key, calendar: historyCalendar) else { return key }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.timeZone = historyCalendar.timeZone
        formatter.dateFormat = "EEE, dd. MMM yyyy"
        return formatter.string(from: date)
    }

    private var calendarSheet: some View {
        NavigationStack {
            List {
                Section {
                    Text("Wähle einen oder mehrere vollständige Tage. Heute zeigt alle Meldungen ab 00:00 Uhr bis jetzt.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Button("Nur heute") { draftDates = [todayKey] }
                    Button("Alle gespeicherten Tage") { draftDates = Set(calendarResponse?.days.map(\.date) ?? [todayKey]) }
                    Button("Auswahl leeren") { draftDates = [] }
                    if !(calendarResponse?.days.contains { $0.date == todayKey } ?? false) {
                        calendarDayRow(key: todayKey, detail: "Heute · noch keine Meldungen")
                    }
                }
                Section("Gespeicherte Tage (\(calendarResponse?.days.count ?? 0))") {
                    ForEach(matchingStoredDays) { day in
                        calendarDayRow(key: day.date, detail: "\(day.count) Meldungen · " + day.networks.map(\.rjProviderName).joined(separator: " · "))
                    }
                }
            }.rjListChrome().navigationTitle("Kalendertage")
                .searchable(text: $dateSearch, prompt: "Datum oder Wochentag")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { showCalendar = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Anzeigen (\(draftDates.count))") {
                            selectedDates = draftDates; selectedDay = nil
                            selectionMode = draftDates == Set([todayKey]) ? "today" : "custom"
                            showCalendar = false
                        }.disabled(draftDates.isEmpty)
                    }
                }
        }.presentationDetents([.large])
    }
    private func calendarDayRow(key: String, detail: String) -> some View {
        Button {
            if draftDates.contains(key) { draftDates.remove(key) } else { draftDates.insert(key) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: draftDates.contains(key) ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(draftDates.contains(key) ? Color.blue : Color.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text(dayTitle(key)).foregroundStyle(.primary)
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            }.padding(.vertical, 4)
        }.buttonStyle(.plain).accessibilityValue(draftDates.contains(key) ? "Ausgewählt" : "")
    }

    private var sourceFilters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(networks, id: \.self) { network in
                    let enabled = enabledNetworks.contains(network)
                    Button {
                        playing = false
                        if enabled { enabledNetworks.remove(network) } else { enabledNetworks.insert(network) }
                        Task { await prepare(preserveSelection: true) }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: network == "unknown" ? "questionmark.circle.fill" : network.rjProviderSymbol)
                            Text(network == "unknown" ? "Unbekannt" : network.rjProviderName)
                            if let count = prepared.sourceCounts[network], enabled { Text("\(count)").monospacedDigit().opacity(0.7) }
                        }
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .foregroundStyle(enabled ? Color.white : Color.primary)
                        .background(enabled ? AnyShapeStyle(network.rjProviderColor.gradient) : AnyShapeStyle(Color(uiColor: .tertiarySystemFill)), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(enabled ? "Ausgewählt" : "Ausgeblendet")
                    .disabled(loading)
                }
            }
        }
    }

    // MARK: Map

    private var rangeText: String {
        guard let first = prepared.points.first, let last = prepared.points.last else { return "" }
        let start = Date(timeIntervalSince1970: TimeInterval(first.timestamp)), end = Date(timeIntervalSince1970: TimeInterval(last.timestamp))
        if historyCalendar.isDate(start, inSameDayAs: end) {
            return start.formatted(date: .omitted, time: .shortened) + " – " + end.formatted(date: .omitted, time: .shortened)
        }
        return start.formatted(.dateTime.day().month(.abbreviated)) + " – " + end.formatted(.dateTime.day().month(.abbreviated))
    }

    private var historyMap: some View {
        HistoryRouteMap(prepared: prepared, selected: selectedPoint, position: $position, satellite: satellite, onSelect: select)
            .frame(height: 380)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(Color.primary.opacity(0.06), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.08), radius: 16, y: 6)
            .overlay(alignment: .topTrailing) {
                RJGlassControls {
                    VStack(spacing: 10) {
                        Button { playing = false; position = .automatic } label: { Image(systemName: "point.topleft.down.to.point.bottomright.curvepath").rjGlassControl() }
                            .accessibilityLabel("Gesamte Auswahl auf Karte zeigen")
                        Button { fullscreen = true } label: { Image(systemName: "arrow.up.left.and.arrow.down.right").rjGlassControl() }
                            .accessibilityLabel("Karte groß öffnen")
                    }
                }.buttonStyle(.plain).font(.body.weight(.medium)).padding(12)
            }
            .overlay(alignment: .bottomLeading) {
                HStack(spacing: 10) {
                    legendDot(.systemTeal, "Früher")
                    LinearGradient(colors: [Color(uiColor: .systemTeal), Color(uiColor: .systemBlue), Color(uiColor: .systemIndigo)], startPoint: .leading, endPoint: .trailing)
                        .frame(width: 44, height: 4).clipShape(Capsule())
                    legendDot(.systemIndigo, "Später")
                }
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 12).padding(.vertical, 8)
                .rjGlass(in: Capsule()).padding(12)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Farbverlauf von früheren zu späteren Meldungen")
            }
            .overlay(alignment: .topLeading) {
                Label(rangeText, systemImage: "clock")
                    .font(.caption.weight(.semibold)).monospacedDigit()
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .rjGlass(in: Capsule()).padding(12)
            }
    }
    private func legendDot(_ color: UIColor, _ text: String) -> some View {
        Text(text).foregroundStyle(.secondary)
    }

    private var fullscreenMap: some View {
        ZStack(alignment: .bottom) {
            HistoryRouteMap(prepared: prepared, selected: selectedPoint, position: $position, satellite: satellite, bottomInset: 300, onSelect: select)
                .ignoresSafeArea()
            playbackPanel(compact: true)
                .padding(16)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
                .shadow(color: .black.opacity(0.15), radius: 20, y: 8)
                .padding(.horizontal, 12).padding(.bottom, 8)
        }
        .overlay(alignment: .topTrailing) {
            RJGlassControls {
                VStack(spacing: 10) {
                    Button { fullscreen = false } label: { Image(systemName: "xmark").rjGlassControl() }
                        .accessibilityLabel("Verlaufkarte schließen")
                    Button { satellite.toggle() } label: { Image(systemName: satellite ? "map" : "globe.europe.africa").rjGlassControl() }
                        .accessibilityLabel(satellite ? "Standardkarte" : "Satellitenkarte")
                    Button { playing = false; position = .automatic } label: { Image(systemName: "point.topleft.down.to.point.bottomright.curvepath").rjGlassControl() }
                        .accessibilityLabel("Gesamte Auswahl auf Karte zeigen")
                }
            }.buttonStyle(.plain).font(.body.weight(.medium)).padding(.trailing, 16).padding(.top, 8)
        }
    }

    // MARK: Playback

    private var playback: some View {
        playbackPanel(compact: false).rjCard()
    }

    private func playbackPanel(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if let point = selectedPoint {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(Date(timeIntervalSince1970: TimeInterval(point.timestamp)), style: .time)
                            .font(.system(.title, design: .rounded).weight(.bold)).monospacedDigit()
                            .contentTransition(.numericText())
                        Text(Date(timeIntervalSince1970: TimeInterval(point.timestamp)).formatted(.dateTime.weekday(.wide).day().month(.wide)))
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 6) {
                        ProviderBadge(provider: point.network ?? "unknown")
                        AccuracyPill(accuracy: point.accuracyM)
                    }
                }
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "mappin.circle.fill").foregroundStyle(.red).font(.title3)
                    ResolvedAddressText(location: point.rjTrackerLocation, fallback: String(format: "%.5f, %.5f", point.latitude, point.longitude))
                        .font(.subheadline.weight(.medium)).lineLimit(2)
                }
                if let first = points.first, let last = points.last, first.timestamp < last.timestamp {
                    VStack(spacing: 6) {
                        HistoryActivityStrip(activity: prepared.activity,
                                             progress: Double((selectedPoint?.timestamp ?? first.timestamp) - first.timestamp) / Double(last.timestamp - first.timestamp))
                            .frame(height: compact ? 22 : 30)
                        Slider(value: Binding(get: { Double(selectedPoint?.timestamp ?? first.timestamp) }, set: { value in
                            followLatest = false
                            selectedIndex = HistoryAnalysis.nearestIndex(to: value, in: points)
                        }), in: Double(first.timestamp)...Double(last.timestamp)) { editing in
                            if editing { playing = false } else { focusSelected() }
                        }
                        .accessibilityLabel("Zeitpunkt auf der Zeitleiste auswählen")
                        HStack {
                            Text(Date(timeIntervalSince1970: TimeInterval(first.timestamp)).formatted(date: .omitted, time: .shortened))
                            Spacer()
                            Text("\(selectedIndex + 1) von \(points.count)").monospacedDigit()
                            Spacer()
                            Text(Date(timeIntervalSince1970: TimeInterval(last.timestamp)).formatted(date: .omitted, time: .shortened))
                        }.font(.caption2).foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 0) {
                    Menu {
                        Picker("Geschwindigkeit", selection: $speed) {
                            Text("0,5×").tag(0.5); Text("1×").tag(1.0); Text("2×").tag(2.0); Text("4×").tag(4.0); Text("8×").tag(8.0)
                        }
                    } label: {
                        Text(speed.formatted(.number.precision(.fractionLength(0...1))) + "×")
                            .font(.subheadline.weight(.bold)).monospacedDigit()
                            .frame(width: 52, height: 44)
                            .background(Color(uiColor: .tertiarySystemFill), in: Capsule())
                    }
                    .accessibilityLabel("Wiedergabegeschwindigkeit")
                    Spacer()
                    Button { step(-1) } label: { Image(systemName: "backward.fill").font(.title2).frame(width: 52, height: 52) }
                        .disabled(selectedIndex == 0).accessibilityLabel("Vorherige Meldung")
                    Button {
                        if selectedIndex >= points.count - 1 { selectedIndex = 0; focusSelected() }
                        playing.toggle()
                    } label: {
                        Image(systemName: playing ? "pause.fill" : "play.fill")
                            .font(.title.weight(.semibold)).foregroundStyle(.white)
                            .frame(width: 66, height: 66)
                            .background(Color.accentColor.gradient, in: Circle())
                            .shadow(color: Color.accentColor.opacity(0.35), radius: 10, y: 4)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .disabled(points.count < 2).accessibilityLabel(playing ? "Wiedergabe pausieren" : "Verlauf abspielen")
                    .padding(.horizontal, 10)
                    Button { step(1) } label: { Image(systemName: "forward.fill").font(.title2).frame(width: 52, height: 52) }
                        .disabled(selectedIndex >= points.count - 1).accessibilityLabel("Nächste Meldung")
                    Spacer()
                    Button { step(points.count); followLatest = true } label: {
                        Image(systemName: "forward.end.fill").font(.subheadline.weight(.bold))
                            .frame(width: 52, height: 44)
                            .background(Color(uiColor: .tertiarySystemFill), in: Capsule())
                    }
                    .disabled(selectedIndex == points.count - 1 && followLatest)
                    .accessibilityLabel("Zur neuesten Meldung")
                }
                .buttonStyle(.plain)
                if !compact {
                    Toggle(isOn: $followSelection) {
                        Label("Karte folgt der Auswahl", systemImage: "scope").font(.subheadline)
                    }.tint(.accentColor)
                }
            }
        }
    }

    // MARK: Summary

    private var metrics: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            metric("Strecke ca.", value: prepared.distanceM >= 1 ? prepared.distanceM.metersText : "–", symbol: "figure.walk.motion", color: .blue)
            metric("Meldungen", value: "\(prepared.points.count)", symbol: "location.fill", color: .green)
            metric("Zeitraum", value: timeSpan, symbol: "clock.fill", color: .orange)
            metric("Genauigkeit", value: prepared.medianAccuracy.map { "±" + $0.metersText } ?? "–", symbol: "scope", color: .purple)
        }
    }
    private var timeSpan: String {
        guard let first = prepared.points.first, let last = prepared.points.last else { return "–" }
        return duration(TimeInterval(last.timestamp - first.timestamp))
    }
    private func metric(_ title: String, value: String, symbol: String, color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.body.weight(.semibold)).foregroundStyle(.white)
                .frame(width: 36, height: 36).background(color.gradient, in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(value).font(.headline).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                Text(title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
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
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("\(visibleStays.count) Aufenthalte").font(.headline)
                Spacer()
                Text("Aus Meldungen abgeleitet").font(.caption).foregroundStyle(.secondary)
            }.padding(.bottom, 8)
            ForEach(Array(visibleStays.prefix(100).enumerated()), id: \.offset) { index, stay in
                Button {
                    playing = false; followLatest = false
                    if let timestamp = stay["start_ts"].numberValue { selectedIndex = HistoryAnalysis.nearestIndex(to: timestamp, in: points) }
                    if let latitude = stay["latitude"].numberValue, let longitude = stay["longitude"].numberValue {
                        let zoom = max(700, (stay["radius_m"].numberValue ?? 100) * 5)
                        position = .region(.init(center: .init(latitude: latitude, longitude: longitude), latitudinalMeters: zoom, longitudinalMeters: zoom))
                    }
                    fullscreen = true
                } label: { HistoryStayRow(stay: stay, last: index == min(visibleStays.count, 100) - 1) }.buttonStyle(.plain)
            }
            if visibleStays.count > 100 { Text("Die 100 neuesten Aufenthalte werden angezeigt.").font(.caption).foregroundStyle(.secondary) }
        }.rjCard()
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
        }.padding(.horizontal, 14).padding(.vertical, 11)
            .background(Color(uiColor: .tertiarySystemFill), in: Capsule())
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 16) {
            RJSectionTitle(title: "Zeit & Datenqualität", subtitle: "\(prepared.points.count) Originalreports · \(points.count) angezeigte \(detailed ? "Reports" : "Stationen")", symbol: "chart.bar.xaxis")
            if let first = points.first, let last = points.last {
                overviewRow("Erste Meldung", value: Date(timeIntervalSince1970: TimeInterval(first.timestamp)).rjTimelineText, symbol: "flag.fill", color: .green)
                overviewRow("Letzte Meldung", value: Date(timeIntervalSince1970: TimeInterval(last.timestamp)).rjTimelineText, symbol: "flag.checkered", color: .indigo)
                overviewRow("Größte Meldungslücke", value: duration(prepared.longestGap), symbol: "clock.badge.questionmark", color: .orange)
            }
            if !prepared.activity.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Meldungsdichte").font(.caption).foregroundStyle(.secondary)
                    HistoryActivityStrip(activity: prepared.activity, progress: nil).frame(height: 44)
                }
            }
            Divider()
            let total = max(1, prepared.sourceCounts.values.reduce(0, +))
            GeometryReader { geometry in
                HStack(spacing: 2) {
                    ForEach(prepared.sourceCounts.keys.sorted(), id: \.self) { network in
                        Rectangle().fill(network.rjProviderColor.gradient)
                            .frame(width: max(4, geometry.size.width * CGFloat(prepared.sourceCounts[network] ?? 0) / CGFloat(total)))
                    }
                }
            }.frame(height: 10).clipShape(Capsule())
            ForEach(prepared.sourceCounts.keys.sorted(), id: \.self) { network in
                HStack {
                    ProviderBadge(provider: network)
                    Spacer()
                    Text("\(prepared.sourceCounts[network] ?? 0) Meldungen · \(Int((Double(prepared.sourceCounts[network] ?? 0) / Double(total) * 100).rounded())) %")
                        .font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
                }
            }
            if let total = response?.matchingTotal, total > (response?.points.count ?? 0) {
                Label("Die neuesten \(response?.points.count ?? 0) von \(total) Meldungen sind geladen. Der Export enthält diesen Ausschnitt.", systemImage: "info.circle")
                    .font(.footnote).foregroundStyle(.orange)
            }
            Text("Genauigkeit ist der Median der gemeldeten Werte. Die Strecke ist eine Schätzung aus Meldungen desselben Netzes; Bewegungen innerhalb der Messgenauigkeit, Lücken und unplausible Sprünge werden nicht gezählt. Linien verbinden Messpunkte und sind keine aufgezeichnete Route.")
                .font(.caption).foregroundStyle(.secondary)
        }.rjCard()
    }
    private func overviewRow(_ title: String, value: String, symbol: String, color: Color) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: symbol).font(.footnote.weight(.semibold)).foregroundStyle(.white)
                .frame(width: 30, height: 30).background(color.gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
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
            }.padding(.horizontal, 4)
            if filteredTimeline.isEmpty {
                ContentUnavailableView.search(text: timelineQuery)
            }
            ForEach(visibleDays) { day in
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(day.date.formatted(.dateTime.weekday(.wide).day().month(.wide))).font(.title3.weight(.semibold))
                        Spacer()
                        Text("\(day.points.count)").font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(.secondary)
                    }.padding(.bottom, 12)
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(day.points.enumerated()), id: \.element.id) { index, point in
                            HistoryTimelineRow(point: point, selected: point.id == selectedPoint?.id, first: index == 0, last: index == day.points.count - 1) {
                                select(point)
                                withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) { proxy.scrollTo("history-map", anchor: .top) }
                            }
                        }
                    }
                }.rjCard()
            }
            if timelineLimit < timelineCount {
                Button("Weitere Meldungen (\(timelineCount - timelineLimit))") { timelineLimit += 100 }
                    .buttonStyle(.bordered).buttonBorderShape(.capsule).frame(maxWidth: .infinity).padding(.vertical, 6)
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
        let input = response?.points ?? []; let networks = enabledNetworks; let calendar = historyCalendar
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
                if !streamSupported { Text("Für den Kalender-Verlauf bitte Backend 20.2 aktualisieren.").font(.caption).foregroundStyle(.orange) }
                else if let liveError { Text(liveError).font(.caption).foregroundStyle(.orange) }
                else if let lastLiveSync { Text("Synchronisiert \(lastLiveSync.formatted(date: .omitted, time: .standard)) · Prüfung alle 5 Sekunden").font(.caption2).foregroundStyle(.secondary) }
            }
            Spacer()
        }.padding(.horizontal, 4)
    }
    @MainActor private func watchHistory() async {
        do { calendarResponse = try await APIClient.shared.historyCalendar(tracker: tracker.ref) }
        catch { liveError = "Kalender nicht verfügbar. Backend 20.2 prüfen." }
        guard !Task.isCancelled else { return }
        if loadedScope != dateScope {
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
        let requestedDates = requestDates; let requestedScope = dateScope
        do {
            var more = true
            while more, !Task.isCancelled {
                let page = try await APIClient.shared.historyStream(tracker: tracker.ref, days: requestedDays, dates: requestedDates, cursor: streamCursor, replay: caughtUp)
                guard requestedScope == dateScope, !Task.isCancelled else { return }
                let previousCount = response?.points.count ?? 0
                if response == nil { response = HistoryResponse(status: "ok", tracker: tracker, points: []) }
                var merged = Dictionary(uniqueKeysWithValues: (response?.points ?? []).map { ($0.id, $0) })
                var changed = false
                for point in page.points {
                    if merged[point.id] != point { changed = true; merged[point.id] = point }
                }
                response?.points = merged.values.filter { requestedDates.contains(HistoryCalendar.key(Date(timeIntervalSince1970: Double($0.timestamp)), calendar: historyCalendar)) }
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
            if requestedScope == dateScope, !Task.isCancelled { liveError = "Aktualisierung fehlgeschlagen. Gespeicherter Stand bleibt sichtbar." }
        }
    }
    @MainActor private func load(force: Bool = false) async {
        let id = UUID(); loadID = id
        loading = response == nil; error = nil
        let requestedDays = days
        let requestedDates = requestDates; let requestedScope = dateScope
        defer { if loadID == id { loading = false } }
        do {
            var loaded = try await APIClient.shared.history(tracker: tracker.ref, days: requestedDays, dates: requestedDates, force: force)
            guard !Task.isCancelled, requestedScope == dateScope, loadID == id else { return }
            let preserve = loadedScope == requestedScope && response != nil
            let originalIDs = reportIDs
            if preserve {
                var merged = Dictionary(uniqueKeysWithValues: (response?.points ?? []).map { ($0.id, $0) })
                for point in loaded.points {
                    if var existing = merged[point.id] {
                        if let address = point.address { existing.address = address; merged[point.id] = existing }
                    } else { merged[point.id] = point }
                }
                loaded.points = merged.values.filter { requestedDates.contains(HistoryCalendar.key(Date(timeIntervalSince1970: Double($0.timestamp)), calendar: historyCalendar)) }
            } else {
                enabledNetworks = Set(loaded.points.map { ($0.network ?? "unknown").rjNormalizedProvider })
                timelineLimit = 60
            }
            let discovered = Set(loaded.points.map { ($0.network ?? "unknown").rjNormalizedProvider })
            enabledNetworks.formUnion(discovered.subtracting(Set(networks)))
            networks = Array(discovered).sorted()
            reportIDs = Set(loaded.points.map(\.id))
            loadedDays = requestedDays; loadedScope = requestedScope; response = loaded
            if !preserve || originalIDs != reportIDs { await prepare(preserveSelection: preserve, stopPlayback: !preserve) }
        } catch is CancellationError { }
        catch {
            guard !Task.isCancelled, requestedScope == dateScope, loadID == id else { return }
            self.error = error.localizedDescription
        }
    }

}


/// Report density as fine bars; the played part is tinted like a progress track.
struct HistoryActivityStrip: View {
    let activity: [Double]
    let progress: Double?
    var body: some View {
        GeometryReader { geometry in
            let count = max(activity.count, 1)
            let spacing: CGFloat = 2
            let width = max(1, (geometry.size.width - spacing * CGFloat(count - 1)) / CGFloat(count))
            HStack(alignment: .bottom, spacing: spacing) {
                ForEach(Array(activity.enumerated()), id: \.offset) { index, value in
                    let played = progress.map { Double(index) / Double(count) <= $0 } ?? true
                    RoundedRectangle(cornerRadius: width / 2, style: .continuous)
                        .fill(played ? AnyShapeStyle(Color.accentColor.gradient) : AnyShapeStyle(Color.secondary.opacity(0.22)))
                        .frame(width: width, height: max(3, geometry.size.height * value))
                }
            }.frame(maxHeight: .infinity, alignment: .bottom)
        }
        .accessibilityHidden(true)
    }
}

struct HistoryTimelineRow: View {
    let point: HistoryPoint
    let selected: Bool
    var first = false
    var last = false
    let action: () -> Void
    private var color: Color { (point.network ?? "unknown").rjProviderColor }
    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Text(Date(timeIntervalSince1970: TimeInterval(point.timestamp)).formatted(date: .omitted, time: .shortened))
                    .font(.subheadline.weight(.semibold)).monospacedDigit()
                    .foregroundStyle(selected ? Color.accentColor : .primary)
                    .frame(width: 50, alignment: .trailing).padding(.top, 2)
                ZStack(alignment: .top) {
                    VStack(spacing: 0) {
                        Rectangle().fill(first ? Color.clear : Color.secondary.opacity(0.22)).frame(width: 2, height: 9)
                        Rectangle().fill(last ? Color.clear : Color.secondary.opacity(0.22)).frame(width: 2).frame(maxHeight: .infinity)
                    }
                    Circle().fill(color.gradient)
                        .frame(width: selected ? 16 : 12, height: selected ? 16 : 12)
                        .overlay(Circle().stroke(Color(uiColor: .secondarySystemGroupedBackground), lineWidth: 2.5))
                        .shadow(color: selected ? color.opacity(0.5) : .clear, radius: 5)
                        .padding(.top, selected ? 3 : 5)
                }.frame(width: 18)
                VStack(alignment: .leading, spacing: 4) {
                    if let address = point.address?.bestText, !address.isEmpty {
                        Text(address).font(.subheadline.weight(.medium)).foregroundStyle(.primary).lineLimit(2)
                    } else {
                        Text("Standort ohne Adresse").font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                        Text(String(format: "%.5f, %.5f", point.latitude, point.longitude)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 6) {
                        Text((point.network ?? "unknown").rjProviderName).foregroundStyle(color)
                        if let accuracy = point.accuracyM, accuracy > 0 { Text("· ±" + accuracy.metersText) }
                        if let reportID = point.reportID { Text("· " + String(reportID.prefix(6))).font(.caption2.monospaced()).foregroundStyle(.tertiary) }
                    }.font(.caption.weight(.medium)).foregroundStyle(.secondary)
                }
                .padding(.bottom, last ? 4 : 18)
                Spacer(minLength: 0)
                if selected { Image(systemName: "location.circle.fill").foregroundStyle(Color.accentColor).font(.title3).padding(.top, 1) }
            }
            .padding(.horizontal, 6).padding(.top, 4)
            .background(selected ? Color.accentColor.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct HistoryStayRow: View {
    let stay: JSONValue
    var last = false
    var body: some View {
        let address = stay["address"]["label"].stringValue ?? stay["address"]["formatted"].stringValue
        let latitude = stay["latitude"].numberValue ?? 0
        let longitude = stay["longitude"].numberValue ?? 0
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "mappin").font(.body.weight(.bold)).foregroundStyle(.white)
                    .frame(width: 38, height: 38).background(Color.red.gradient, in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text(address ?? String(format: "%.5f, %.5f", latitude, longitude))
                        .font(.subheadline.weight(.semibold)).foregroundStyle(.primary).lineLimit(2)
                    if let start = stay["start_ts"].numberValue, let end = stay["end_ts"].numberValue {
                        Text("\(Date(timeIntervalSince1970: start).rjTimelineText) – \(Date(timeIntervalSince1970: end).formatted(date: .omitted, time: .shortened))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 8) {
                        Text("\(stay["report_count"].integer) Reports").font(.caption).foregroundStyle(.secondary)
                        if let accuracy = stay["median_accuracy_m"].numberValue, accuracy > 0 { AccuracyPill(accuracy: accuracy) }
                    }
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 6) {
                    Text(stay["duration_text"].stringValue ?? "").font(.subheadline.weight(.bold)).foregroundStyle(Color.accentColor)
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                }
            }.padding(.vertical, 10)
            if !last { Divider().padding(.leading, 50) }
        }.contentShape(Rectangle())
    }
}
