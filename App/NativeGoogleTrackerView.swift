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
    private var tracker: GoogleTrackerSnapshot? { google.trackers.first { $0.id == deviceID } }
    var body: some View {
        Form {
            if let tracker {
                Section {
                    HStack(alignment: .top, spacing: 8) {
                        TrackerLocationSummary(symbol: model.trackers.first(where: { $0.provider == "google" && $0.apiID == deviceID })?.emoji ?? "📡",
                            provider: "google", location: displayLocation(tracker),
                            timestamp: displayLocation(tracker)?.timestamp, nearby: tracker.nearby)
                        Button { google.setFavorite(deviceID, enabled: !google.favorite(deviceID)) } label: {
                            Image(systemName: google.favorite(deviceID) ? "star.fill" : "star").foregroundStyle(.orange).frame(width: 44, height: 44)
                        }.buttonStyle(.plain).accessibilityLabel("Favorit umschalten")
                    }
                }.listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                Section {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) { refreshTile; routeTile(tracker) }
                        VStack(spacing: 12) { refreshTile; routeTile(tracker) }
                    }.listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
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
        .refreshable { await google.refreshLocation(deviceID) }
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
    private func updateLocation() {
        google.clearError()
        do { try google.locate(deviceID) } catch { message = error.localizedDescription }
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
        NavigationLink { GoogleNearbyView(deviceID: deviceID) } label: {
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
    @State private var reports: [GoogleReportSnapshot] = []
    var body: some View {
        List {
            Section {
                Text("\(reports.count) unterschiedliche Meldungen").font(.headline)
                Text("Alle gelieferten Reports werden berücksichtigt. Wiederholungen werden zusammengeführt; Zeit, Quelle und Genauigkeit bleiben erhalten.").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(reports) { report in
                VStack(alignment: .leading, spacing: 5) {
                    HStack { Text(report.date, format: .dateTime.day().month().year().hour().minute().second()).font(.subheadline.weight(.medium)); Spacer() }
                    Text(report.label ?? (report.latitude == nil ? "Noch verschlüsselt" : "Standortmeldung")).font(.subheadline)
                    HStack {
                        Text(report.own ? "Eigene Sichtung" : "Google-Netzwerk")
                        if let accuracy = report.accuracy, accuracy > 0 { Text("± \(Int(accuracy)) m") }
                        Text(googleReportKind(report.kind))
                    }.font(.caption).foregroundStyle(.secondary)
                    if let lat = report.latitude, let lon = report.longitude {
                        NavigationLink("Auf Karte ansehen") {
                            Map(initialPosition: .region(.init(center: .init(latitude: lat, longitude: lon), latitudinalMeters: 800, longitudinalMeters: 800))) {
                                Marker("Meldung", coordinate: .init(latitude: lat, longitude: lon)).tint(.green)
                            }.navigationTitle(report.date.formatted(date: .abbreviated, time: .shortened))
                        }.font(.caption)
                    }
                }.padding(.vertical, 5)
            }
        }.rjListChrome().navigationTitle("Google-Verlauf").navigationBarTitleDisplayMode(.inline)
            .task(id: google.trackers.first(where: { $0.id == deviceID })) {
                let result = await google.reports(for: deviceID)
                if !Task.isCancelled { reports = result }
            }
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

