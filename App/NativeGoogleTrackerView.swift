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
                    HStack(spacing: 14) {
                        AsyncImage(url: URL(string: tracker.imageURL)) { image in
                            if let image = image.image { image.resizable().scaledToFit() }
                            else { Image(systemName: "sensor.tag.radiowaves.forward.fill").font(.largeTitle).foregroundStyle(.green) }
                        }.frame(width: 58, height: 58)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(tracker.name).font(.title2.bold())
                            Label("Google · direkt verbunden", systemImage: "lock.iphone").font(.caption).foregroundStyle(.secondary)
                            if let date = tracker.reportedAt { Text(date, style: .relative).font(.caption).foregroundStyle(.secondary) }
                        }
                    }.padding(.vertical, 8).accessibilityIdentifier("tracker-detail-header")
                    if let lat = tracker.latitude, let lon = tracker.longitude {
                        Map(initialPosition: .region(.init(center: .init(latitude: lat, longitude: lon), latitudinalMeters: 1000, longitudinalMeters: 1000))) {
                            Marker(tracker.name, systemImage: "sensor.tag.radiowaves.forward.fill", coordinate: .init(latitude: lat, longitude: lon)).tint(.green)
                            if let accuracy = tracker.accuracy, accuracy > 0 { MapCircle(center: .init(latitude: lat, longitude: lon), radius: accuracy).foregroundStyle(.green.opacity(0.12)) }
                        }.frame(height: 190).clipShape(RoundedRectangle(cornerRadius: 18))
                    }
                    if let battery = tracker.battery { LabeledContent("Batterie", value: battery) }
                    LabeledContent("Gespeicherte Meldungen", value: String(tracker.reportCount))
                }
                Section("Finden") {
                    Button { run { try google.locate(deviceID) } } label: {
                        Label(google.locating.contains(deviceID) ? "Sammle weitere Reports …" : "Standort aktualisieren", systemImage: "location.fill")
                    }.disabled(google.locating.contains(deviceID))
                    Button("Klingeln lassen", systemImage: "speaker.wave.2.fill") { run { try await google.ring(deviceID); message = tracker.nearby ? "Bluetooth-Klingeln bestätigt." : "Klingeln bei Google angefragt." } }
                    Button("Google-Klingelanfrage stoppen", systemImage: "speaker.slash") { run { try await google.ring(deviceID, stop: true) } }
                    NavigationLink { GoogleNearbyView(deviceID: deviceID) } label: { Label("In der Nähe suchen", systemImage: "dot.radiowaves.left.and.right") }
                    NavigationLink { GoogleUWBLabView(deviceID: deviceID) } label: { Label("UWB prüfen · experimentell", systemImage: "dot.scope") }
                        .accessibilityIdentifier("google-uwb-lab")
                    if let lat = tracker.latitude, let lon = tracker.longitude {
                        Button("Route öffnen", systemImage: "arrow.triangle.turn.up.right.diamond") {
                            MKMapItem(placemark: MKPlacemark(coordinate: .init(latitude: lat, longitude: lon))).openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
                        }
                    }
                }
                Section {
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
        .disabled(busy)
        .refreshable { await google.refresh() }
        .alert("Trackernamen ändern", isPresented: $editing) {
            TextField("Name", text: $name)
            Button("Speichern") { run { try await google.rename(deviceID, name: name) } }
            Button("Abbrechen", role: .cancel) {}
        }
    }
    private func run(_ action: @escaping @MainActor () async throws -> Void) {
        busy = true; message = nil; google.clearError()
        Task { @MainActor in defer { busy = false }; do { try await action() } catch { message = error.localizedDescription } }
    }
}

struct NativeGoogleHistoryView: View {
    let deviceID: String
    @ObservedObject private var google = GoogleTrackerStore.shared
    private var reports: [GoogleReportSnapshot] { google.reports(for: deviceID) }
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
                        Text(report.kind)
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
