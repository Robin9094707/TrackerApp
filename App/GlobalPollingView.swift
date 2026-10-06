import SwiftUI

struct GlobalPollingView: View {
    @Environment(AppModel.self) private var model
    @State private var enabled: Bool?
    @State private var error: String?
    @State private var interval = "–"
    @State private var updating = false
    var body: some View {
        List {
            Section {
                LabeledContent("Automatische Ortung", value: enabled.map { $0 ? "Aktiv" : "Pausiert" } ?? "Wird geladen …")
                LabeledContent("Apple-Reportabruf", value: interval)
                Text("Apple-Verläufe speichern alle eindeutigen Reports eines Batches. Neue Meldungen hängen vom Find-My-Netz ab.").font(.caption).foregroundStyle(.secondary)
                Button("Apple auf festen 20-Sekunden-Abruf setzen") { Task { await setAppleCadence() } }.disabled(updating)
                Text("Die Änderung gilt serverweit für automatische Abrufe aller Ortungsnetze.").font(.subheadline).foregroundStyle(.secondary)
            }
            if let enabled {
                NavigationLink(enabled ? "Automatik pausieren" : "Automatik fortsetzen") {
                    ManagementForm(title: enabled ? "Automatik pausieren" : "Automatik fortsetzen", path: "/api/mobile/v1/action", constants: ["action": .string("global_pause"), "paused": .bool(enabled)], confirmation: enabled ? "Alle automatischen Ortungsabrufe pausieren?" : "Automatische Ortungsabrufe wieder aktivieren?") { _ in self.enabled = !enabled; Task { await model.refresh() } }
                }
            }
            if let error { Text(error).foregroundStyle(.red) }
        }.scrollContentBackground(.hidden).rjScreenChrome().navigationTitle("Automatische Ortung").navigationBarTitleDisplayMode(.inline)
        .task { await load() }.refreshable { await load() }
    }
    private func load() async {
        do {
            let polling = try await APIClient.shared.requestJSON(path: "/api/polling/settings")["polling"]
            enabled = polling["enabled"].boolValue
            let apple = polling["providers"]["apple"]
            let minimum = apple["interval_min"].integer; let maximum = apple["interval_max"].integer
            interval = minimum == maximum ? "\(minimum) Sekunden" : "\(minimum)–\(maximum) Sekunden"
            error = nil
        } catch { self.error = error.localizedDescription }
    }
    private func setAppleCadence() async {
        updating = true; defer { updating = false }
        do {
            _ = try await APIClient.shared.requestJSON(path: "/api/polling/settings", method: "POST", json: ["apple": ["interval_min": 20, "interval_max": 20]])
            await load(); Haptics.success()
        } catch { self.error = error.localizedDescription }
    }
}


