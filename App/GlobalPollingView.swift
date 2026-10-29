import SwiftUI

struct GlobalPollingView: View {
    @Environment(AppModel.self) private var model
    @State private var enabled: Bool?
    @State private var error: String?
    @State private var interval = "–"
    @State private var googleInterval = "–"
    @State private var updating = false
    @State private var googlePaused: Bool?
    @State private var googlePausedDevices: Set<String> = []
    private var googleTrackers: [Tracker] { model.trackers.filter { $0.provider == "google" } }
    var body: some View {
        List {
            Section {
                LabeledContent("Automatische Ortung", value: enabled.map { $0 ? "Aktiv" : "Pausiert" } ?? "Wird geladen …")
                LabeledContent("Apple-Reportabruf", value: interval)
                LabeledContent("Google-Abruf (Server)", value: googleInterval)
                Text("Apple-Verläufe speichern alle eindeutigen Reports eines Batches. Neue Meldungen hängen vom Find-My-Netz ab.").font(.caption).foregroundStyle(.secondary)
                Button("Apple auf festen 20-Sekunden-Abruf setzen") { Task { await setAppleCadence() } }.disabled(updating)
                Text("Die Änderung gilt serverweit für automatische Abrufe aller Ortungsnetze.").font(.subheadline).foregroundStyle(.secondary)
            }
            if let enabled {
                NavigationLink(enabled ? "Automatik pausieren" : "Automatik fortsetzen") {
                    ManagementForm(title: enabled ? "Automatik pausieren" : "Automatik fortsetzen", path: "/api/mobile/v1/action", constants: ["action": .string("global_pause"), "paused": .bool(enabled)], confirmation: enabled ? "Alle automatischen Ortungsabrufe pausieren?" : "Automatische Ortungsabrufe wieder aktivieren?") { _ in self.enabled = !enabled; Task { await model.refresh() } }
                }
            }
            if let googlePaused {
                Section {
                    Toggle(isOn: Binding(get: { googlePaused }, set: { value in Task { await setGoogleCollection(paused: value) } })) {
                        Label("Google-Erfassung auf dem Server pausieren", systemImage: "pause.circle.fill")
                    }
                    .disabled(updating)
                    .accessibilityIdentifier("google-server-collection-pause")
                    if !googlePaused, !googleTrackers.isEmpty {
                        ForEach(googleTrackers) { tracker in
                            Toggle(isOn: Binding(get: { googlePausedDevices.contains(tracker.apiID) }, set: { value in
                                Task { await setGoogleCollection(device: tracker.apiID, paused: value) }
                            })) {
                                Label { Text(tracker.name) } icon: { Text(tracker.emoji ?? "📍") }
                            }.disabled(updating)
                        }
                    }
                } header: { Text("Google auf dem Server") } footer: {
                    Text(googlePaused
                         ? "Der Server fragt Google nicht mehr automatisch ab und speichert keinen neuen Google-Verlauf. Bereits gespeicherte Daten bleiben erhalten. Google direkt auf diesem iPhone funktioniert unverändert."
                         : "Einzelne Google-Tracker können von der Servererfassung ausgenommen werden. Manuelle Ortung aktualisiert weiterhin nur den aktuellen Standort.")
                }
            }
            if let error { Text(error).foregroundStyle(.red) }
        }.scrollContentBackground(.hidden).rjScreenChrome().navigationTitle("Automatische Ortung").navigationBarTitleDisplayMode(.inline)
        .task { await load() }.refreshable { await load() }
    }
    private func load() async {
        do {
            let polling = try await APIClient.shared.requestJSON(path: "/api/polling/settings")["polling"]
            apply(polling)
            error = nil
        } catch { self.error = error.localizedDescription }
    }
    private func apply(_ polling: JSONValue) {
        enabled = polling["enabled"].boolValue
        interval = cadence(polling["providers"]["apple"])
        googleInterval = cadence(polling["providers"]["google"])
        // Backends before 20.5 do not report the switch; the section stays hidden there.
        let collection = polling["google_server_collection"]
        googlePaused = collection["paused"].boolValue
        if case .array(let rows) = collection["paused_devices"] { googlePausedDevices = Set(rows.compactMap(\.stringValue)) }
    }
    private func cadence(_ provider: JSONValue) -> String {
        let minimum = provider["interval_min"].integer; let maximum = provider["interval_max"].integer
        guard minimum > 0 else { return "–" }
        return minimum == maximum ? "\(minimum) Sekunden" : "\(minimum)–\(maximum) Sekunden"
    }
    private func setAppleCadence() async {
        updating = true; defer { updating = false }
        do {
            _ = try await APIClient.shared.requestJSON(path: "/api/polling/settings", method: "POST", json: ["apple": ["interval_min": 20, "interval_max": 20]])
            await load(); Haptics.success()
        } catch { self.error = error.localizedDescription }
    }
    private func setGoogleCollection(device: String? = nil, paused: Bool) async {
        updating = true; defer { updating = false }
        var collection: [String: Any] = [:]
        if let device { collection["devices"] = [device: paused] } else { collection["paused"] = paused }
        do {
            let response = try await APIClient.shared.requestJSON(path: "/api/polling/settings", method: "POST", json: ["google_server_collection": collection])
            apply(response["polling"]); error = nil
            Haptics.success()
        } catch { self.error = error.localizedDescription; Haptics.warning() }
    }
}
