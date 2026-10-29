import SwiftUI
import MapKit
import SpotIntegration

struct NativeGoogleTrackerView: View {
    @Environment(AppModel.self) private var model
    let deviceID: String
    @ObservedObject private var google = GoogleTrackerStore.shared
    @State private var busy = false
    @State private var message: String?
    @State private var name = ""
    @State private var editing = false
    @State private var share: String?
    @State private var showNearby = false
    private var tracker: GoogleTrackerSnapshot? { google.trackers.first { $0.id == deviceID } }
    var body: some View {
        Form {
            if let tracker {
                Section {
                    HStack(alignment: .top, spacing: 8) {
                        TrackerLocationSummary(symbol: model.trackers.first(where: { $0.provider == "google" && $0.apiID == deviceID })?.emoji ?? "📡",
                            provider: "google", location: displayLocation(tracker),
                            timestamp: displayLocation(tracker)?.timestamp, nearby: tracker.nearby)
                        Button { toggleFavorite() } label: {
                            Image(systemName: google.favorite(deviceID) ? "star.fill" : "star").foregroundStyle(.orange).frame(width: 44, height: 44)
                        }.buttonStyle(.plain).accessibilityLabel("Favorit umschalten")
                    }
                }.listRowBackground(Color.clear).listRowInsets(EdgeInsets())
                Section {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) { refreshTile; routeTile(tracker) }
                        VStack(spacing: 12) { refreshTile; routeTile(tracker) }
                    }.padding(.bottom, 12).listRowInsets(EdgeInsets()).listRowBackground(Color.clear).listRowSeparator(.hidden)
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) { ringTile(tracker); nearbyTile }
                        VStack(spacing: 12) { ringTile(tracker); nearbyTile }
                    }.listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                }
                if google.locating.contains(deviceID) {
                    Section { ProgressView("Warte auf Google-Antwort …").font(.footnote) }
                } else if let status = google.locationStatus[deviceID] {
                    Section { Text(status).font(.footnote).foregroundStyle(.secondary) }
                }
                Section("Finden") {
                    Button("Google-Klingelanfrage stoppen", systemImage: "speaker.slash") { run { try await google.ring(deviceID, stop: true) } }
                    NavigationLink { GoogleUWBLabView(deviceID: deviceID) } label: { Label("UWB prüfen · experimentell", systemImage: "dot.scope") }
                        .accessibilityIdentifier("google-uwb-lab")

                }
                Section("Standortverlauf") {
                    Toggle("Verlauf automatisch sammeln", isOn: Binding(get: { tracker.historyEnabled }, set: { google.setHistoryEnabled(deviceID, enabled: $0) }))
                    Text("Automatische Abrufe verwenden das Intervall in den Google-Einstellungen. Manuelle Einzelabrufe bleiben möglich und werden ebenfalls gespeichert.").font(.caption).foregroundStyle(.secondary)
                    NavigationLink { NativeGoogleHistoryView(deviceID: deviceID) } label: { Label("Alle \(tracker.reportCount) Reports ansehen", systemImage: "clock.arrow.circlepath") }
                        .accessibilityIdentifier("tracker-history-link")
                    if let serverTracker = model.bootstrap?.trackers.first(where: { $0.provider == "google" && $0.apiID == deviceID }) {
                        NavigationLink { TrackerDetailView(tracker: serverTracker, preferNativeGoogle: false) } label: {
                            Label("Bisheriger Serververlauf & Automationen", systemImage: "externaldrive.badge.icloud")
                        }
                    }
                    if !tracker.unlocked {
                        NavigationLink { GoogleAccountView() } label: { Label("Google-Schlüssel entsperren", systemImage: "lock.open") }
                        Text("Verschlüsselte Reports bleiben erhalten und werden nach dem Entsperren erneut verarbeitet.").font(.caption).foregroundStyle(.secondary)
                    }
                    NavigationLink { GoogleAccountView() } label: { Label("Aktualisierung & Google-Konto", systemImage: "arrow.triangle.2.circlepath") }
                }
                if google.motorolaModel(deviceID) != nil {
                    Section("Motorola") {
                        NavigationLink { MotorolaFirmwareView(deviceID: deviceID) } label: {
                            Label("Moto-Tag-Firmware aktualisieren", systemImage: "arrow.down.circle")
                        }.accessibilityIdentifier("motorola-firmware-link")
                    }
                }
                Section("Über dieses Objekt") {
                    LabeledContent("Netzwerk", value: "Google")
                    LabeledContent("Batterie", value: tracker.battery.map(TrackerTimeText.battery) ?? "Unbekannt")
                    if let date = tracker.reportedAt {
                        LabeledContent("Zuletzt gesehen", value: date.formatted(.dateTime.locale(TrackerTimeText.locale).day().month().year().hour().minute()))
                    }
                    if let accuracy = tracker.accuracy, accuracy > 0 { LabeledContent("Genauigkeit", value: "±" + accuracy.metersText) }
                }
                Section("Verwalten") {
                    Button("Namen ändern", systemImage: "pencil") { name = tracker.name; editing = true }
                    Toggle("Verloren-Modus", isOn: Binding(get: { tracker.isLost }, set: { enabled in run { try await google.setLost(deviceID, enabled: enabled) } }))
                    Button("Google-Freigabelink erstellen", systemImage: "person.badge.plus") { run { share = try await google.sharingLink(deviceID) } }
                    if let share, let url = URL(string: share) { ShareLink(item: url) { Label("Freigabelink teilen", systemImage: "square.and.arrow.up") } }
                    Button("Ausstehende Freigabe bestätigen") { run { try await google.approveSharing(deviceID) } }
                    ForEach(tracker.sharedWith, id: \.self) { email in
                        HStack { Text(email).font(.footnote); Spacer(); Button("Entfernen", role: .destructive) { run { try await google.removeSharing(deviceID, email: email) } } }
                    }
                }
            } else { Text("Tracker wird geladen. Bitte aktualisieren.").foregroundStyle(.secondary) }
            if busy { ProgressView("Bitte warten …") }
            if let message { Text(message).font(.footnote).foregroundStyle(.secondary).textSelection(.enabled) }
            if let error = google.errorMessage { Text(error).font(.footnote).foregroundStyle(.orange) }
        }
        .rjListChrome().navigationTitle(tracker?.name ?? "Google-Tracker").navigationBarTitleDisplayMode(.inline)
        .listSectionSpacing(14)
        .contentMargins(.top, 8, for: .scrollContent)
        .refreshable { await model.locateGoogle(deviceID) }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { updateLocation() } label: {
                    if google.locating.contains(deviceID) { ProgressView() }
                    else { Image(systemName: "arrow.clockwise") }
                }.disabled(google.locating.contains(deviceID))
                    .accessibilityLabel("Standort aktualisieren")
                    .accessibilityIdentifier("google-refresh-location")
            }
        }
        .navigationDestination(isPresented: $showNearby) { GoogleNearbyView(deviceID: deviceID) }
        .alert("Trackernamen ändern", isPresented: $editing) {
            TextField("Name", text: $name)
            Button("Speichern") { run { try await google.rename(deviceID, name: name) } }
            Button("Abbrechen", role: .cancel) {}
        }
    }
    private func displayLocation(_ tracker: GoogleTrackerSnapshot) -> TrackerLocation? {
        if let merged = model.trackers.first(where: { $0.provider == "google" && $0.apiID == deviceID }),
           merged.reportTimestamp >= Int(tracker.reportedAt?.timeIntervalSince1970 ?? 0), let location = merged.validLocation {
            return location
        }
        guard let lat = tracker.latitude, let lon = tracker.longitude else { return nil }
        return TrackerLocation(latitude: lat, longitude: lon, accuracyM: tracker.accuracy,
            timestamp: tracker.reportedAt.map { Int($0.timeIntervalSince1970) }, network: "google", provider: "google")
    }
    private func toggleFavorite() {
        if let tracker = model.trackers.first(where: { $0.provider == "google" && $0.apiID == deviceID }) {
            Task { await model.setFavorite(tracker) }
        } else { google.setFavorite(deviceID, enabled: !google.favorite(deviceID)) }
    }
    private func updateLocation() {
        google.clearError()
        Task { await model.locateGoogle(deviceID) }
    }
    private var refreshTile: some View {
        Button { updateLocation() } label: {
            TrackerActionTile(title: google.locating.contains(deviceID) ? "Wird geortet …" : "Jetzt orten",
                subtitle: "Standort aktualisieren", symbol: "location.fill", color: .green)
        }.buttonStyle(.plain).disabled(google.locating.contains(deviceID))
            .accessibilityIdentifier("google-locate-tile")
    }
    private func routeTile(_ tracker: GoogleTrackerSnapshot) -> some View {
        Menu {
            Button("Zu Fuß", systemImage: "figure.walk") { openMaps(tracker, mode: MKLaunchOptionsDirectionsModeWalking) }
            Button("Mit dem Auto", systemImage: "car") { openMaps(tracker, mode: MKLaunchOptionsDirectionsModeDriving) }
            Button("Mit Bus & Bahn", systemImage: "tram") { openMaps(tracker, mode: MKLaunchOptionsDirectionsModeTransit) }
        } label: {
            TrackerActionTile(title: "Route", subtitle: "In Karten öffnen", symbol: "arrow.triangle.turn.up.right.diamond.fill")
        }.buttonStyle(.plain).disabled(tracker.latitude == nil || tracker.longitude == nil)
    }
    private func openMaps(_ tracker: GoogleTrackerSnapshot, mode: String) {
        guard let location = displayLocation(tracker) else { return }
        let item = MKMapItem(placemark: MKPlacemark(coordinate: location.coordinate))
        item.name = tracker.name
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: mode])
    }
    private func ringTile(_ tracker: GoogleTrackerSnapshot) -> some View {
        Button { run { try await google.ring(deviceID); message = tracker.nearby ? "Bluetooth-Klingeln bestätigt." : "Klingeln bei Google angefragt." } } label: {
            TrackerActionTile(title: "Ton abspielen", subtitle: tracker.nearby ? "In deiner Nähe" : "Über Google", symbol: "speaker.wave.2.fill", color: .indigo)
        }.buttonStyle(.plain).disabled(busy)
    }
    private var nearbyTile: some View {
        Button { showNearby = true } label: {
            TrackerActionTile(title: "Suchen", subtitle: "In der Nähe", symbol: "arrow.up", color: .green)
        }.buttonStyle(.plain)
    }
    private func run(_ action: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }
        busy = true; message = nil; google.clearError()
        Task { @MainActor in defer { busy = false }; do { try await action() } catch { message = error.localizedDescription } }
    }
}

struct NativeGoogleHistoryView: View {
    let deviceID: String
    @ObservedObject private var google = GoogleTrackerStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var reports: [GoogleReportSnapshot] = []
    @State private var prepared = PreparedHistory()
    @State private var selectedDay: Date?
    @State private var selectedIndex = 0
    @State private var position: MapCameraPosition = .automatic
    @State private var limit = 80
    private var points: [HistoryPoint] { prepared.displayPoints }
    private var selected: HistoryPoint? { points.isEmpty ? nil : points[min(max(selectedIndex, 0), points.count - 1)] }
    private var lockedCount: Int { reports.filter { $0.latitude == nil }.count }
    private var labels: [String: String] {
        Dictionary(reports.compactMap { report in report.label.map { ("google:" + report.id, $0) } }, uniquingKeysWith: { first, _ in first })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(selectedDay.map { $0.formatted(.dateTime.weekday(.wide).day().month(.wide)) } ?? "Alle Meldungen").font(.largeTitle.bold())
                    Text("\(reports.count) unterschiedliche Meldungen" + (lockedCount > 0 ? " · \(lockedCount) noch verschlüsselt" : ""))
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                if !prepared.availableDays.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            chip("Alle", detail: "\(prepared.availableDays.count) Tage", day: nil)
                            ForEach(prepared.availableDays) { day in
                                chip(day.date.formatted(.dateTime.weekday(.abbreviated).day()), detail: "\(day.points.count)", day: day.date)
                            }
                        }
                    }
                }
                if points.isEmpty {
                    ContentUnavailableView("Keine entschlüsselten Standorte", systemImage: "lock.circle",
                                           description: Text("Sobald Google-Meldungen entschlüsselt sind, erscheinen sie hier mit Karte und Zeitleiste.")).rjCard()
                } else {
                    HistoryRouteMap(prepared: prepared, selected: selected, position: $position, onSelect: select)
                        .frame(height: 340)
                        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                        .shadow(color: .black.opacity(0.08), radius: 16, y: 6)
                        .overlay(alignment: .topTrailing) {
                            Button { position = .automatic } label: { Image(systemName: "point.topleft.down.to.point.bottomright.curvepath").rjGlassControl() }
                                .buttonStyle(.plain).padding(12).accessibilityLabel("Gesamte Auswahl auf Karte zeigen")
                        }
                    if let point = selected, let first = points.first, let last = points.last {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(Date(timeIntervalSince1970: TimeInterval(point.timestamp)), style: .time)
                                    .font(.system(.title, design: .rounded).weight(.bold)).monospacedDigit()
                                Spacer()
                                AccuracyPill(accuracy: point.accuracyM)
                            }
                            ResolvedAddressText(location: point.rjTrackerLocation, fallback: labels[point.id] ?? String(format: "%.5f, %.5f", point.latitude, point.longitude))
                                .font(.subheadline.weight(.medium))
                            if first.timestamp < last.timestamp {
                                HistoryActivityStrip(activity: prepared.activity, progress: Double(point.timestamp - first.timestamp) / Double(last.timestamp - first.timestamp)).frame(height: 26)
                                Slider(value: Binding(get: { Double(point.timestamp) }, set: { selectedIndex = HistoryAnalysis.nearestIndex(to: $0, in: points) }),
                                       in: Double(first.timestamp)...Double(last.timestamp)) { editing in if !editing { focus() } }
                                    .accessibilityLabel("Zeitpunkt auswählen")
                            }
                            HStack {
                                Label(prepared.distanceM >= 1 ? "ca. " + prepared.distanceM.metersText : "Keine Bewegung", systemImage: "figure.walk.motion")
                                Spacer()
                                Text("\(selectedIndex + 1) von \(points.count)").monospacedDigit()
                            }.font(.caption).foregroundStyle(.secondary)
                        }.rjCard()
                    }
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(visibleDays) { day in
                            VStack(alignment: .leading, spacing: 0) {
                                HStack {
                                    Text(day.date.formatted(.dateTime.weekday(.wide).day().month(.wide))).font(.title3.weight(.semibold))
                                    Spacer()
                                    Text("\(day.points.count)").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                                }.padding(.bottom, 12)
                                ForEach(Array(day.points.enumerated()), id: \.element.id) { index, point in
                                    HistoryTimelineRow(point: point, selected: point.id == selected?.id, first: index == 0, last: index == day.points.count - 1) { select(point) }
                                }
                            }.rjCard()
                        }
                        if limit < points.count {
                            Button("Weitere Meldungen") { limit += 120 }.buttonStyle(.bordered).buttonBorderShape(.capsule).frame(maxWidth: .infinity)
                                .onAppear { limit += 120 }
                        }
                    }
                }
                Text("Alle gelieferten Reports werden berücksichtigt. Wiederholungen werden zusammengeführt; Zeit, Quelle und Genauigkeit bleiben erhalten. Die Anzeige bündelt nahe Meldungen, ohne gespeicherte Daten zu verändern.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(16)
        }
        .rjScreenChrome().navigationTitle("Google-Verlauf").navigationBarTitleDisplayMode(.inline)
        .task(id: google.trackers.first(where: { $0.id == deviceID })) {
            let result = await google.reports(for: deviceID)
            if !Task.isCancelled { reports = result; await prepare(resetSelection: prepared.points.isEmpty) }
        }
        .onChange(of: selectedDay) { _, _ in Task { await prepare(resetSelection: true) } }
    }

    private var visibleDays: [HistoryDay] {
        var remaining = limit
        return prepared.days.compactMap { day in
            guard remaining > 0 else { return nil }
            let visible = Array(day.points.prefix(remaining)); remaining -= visible.count
            return HistoryDay(date: day.date, points: visible)
        }
    }

    private func chip(_ title: String, detail: String, day: Date?) -> some View {
        let active = selectedDay == day
        return Button { selectedDay = day } label: {
            VStack(spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption2).opacity(0.75)
            }
            .padding(.horizontal, 14).padding(.vertical, 9)
            .foregroundStyle(active ? Color.white : .primary)
            .background(active ? AnyShapeStyle(Color.accentColor.gradient) : AnyShapeStyle(Color(uiColor: .secondarySystemGroupedBackground)), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }.buttonStyle(.plain).accessibilityAddTraits(active ? .isSelected : [])
    }

    private func select(_ point: HistoryPoint) {
        if let index = prepared.indexByID[point.id] { selectedIndex = index; focus(); Haptics.impact() }
    }
    private func focus() {
        guard let point = selected else { return }
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) {
            position = .region(RJMapCamera.focusedRegion(for: point.rjTrackerLocation, zoomMeters: max(1200, (point.accuracyM ?? 100) * 6)))
        }
    }
    @MainActor private func prepare(resetSelection: Bool) async {
        let input = reports.compactMap { report -> HistoryPoint? in
            guard let lat = report.latitude, let lon = report.longitude else { return nil }
            return HistoryPoint(latitude: lat, longitude: lon, accuracyM: report.accuracy, timestamp: Int(report.date.timeIntervalSince1970),
                                network: "google", reportID: report.id)
        }
        let day = selectedDay
        let result = await Task.detached(priority: .userInitiated) {
            HistoryAnalysis.prepare(input, networks: ["google"], day: day)
        }.value
        guard !Task.isCancelled else { return }
        let previous = selected?.id
        prepared = result
        if resetSelection { selectedIndex = max(0, result.displayPoints.count - 1); limit = 80; position = .automatic }
        else if let previous { selectedIndex = result.indexByID[previous] ?? max(0, result.displayPoints.count - 1) }
    }
}

private func googleReportKind(_ kind: String) -> String {
    switch kind.lowercased() {
    case "aggregated": return "Gebündelte Meldung"
    case "recent", "lastknown": return "Letzter bekannter Standort"
    case "unknown", "unspecified": return "Standortmeldung"
    default: return "Standortmeldung"
    }
}

struct GoogleNearbyView: View {
    let deviceID: String
    @ObservedObject private var google = GoogleTrackerStore.shared
    @State private var message: String?
    private var tracker: GoogleTrackerSnapshot? { google.trackers.first { $0.id == deviceID } }
    var body: some View {
        VStack(spacing: 26) {
            Spacer()
            Image(systemName: "dot.radiowaves.left.and.right").font(.system(size: 76)).foregroundStyle(tracker?.nearby == true ? .green : .blue)
            Text(tracker?.name ?? "Tracker suchen").font(.title.bold())
            Text(tracker?.nearby == true ? "Bluetooth-Signal empfangen" : "Suche in deiner Umgebung …").font(.headline)
            if let signal = tracker?.signal {
                ProgressView(value: min(1, max(0, (signal + 100) / 70))).tint(.green).padding(.horizontal, 40)
                Text("\(Int(signal)) dBm · stärkeres Signal bedeutet meist näher").font(.caption).foregroundStyle(.secondary)
            }
            Text("Bewege dich langsam. Die Anzeige verwendet Bluetooth-Signalstärke.").multilineTextAlignment(.center).foregroundStyle(.secondary)
            Button("Klingeln lassen", systemImage: "speaker.wave.2.fill") { Task { do { try await google.ring(deviceID) } catch { message = error.localizedDescription } } }.buttonStyle(.borderedProminent)
            if let message { Text(message).font(.footnote).foregroundStyle(.orange) }
            Spacer()
        }.padding(24).rjScreenChrome().navigationTitle("Nahsuche").navigationBarTitleDisplayMode(.inline)
            .onAppear { google.beginNearby(deviceID) }.onDisappear { google.endNearby() }
    }
}

