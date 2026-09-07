import SwiftUI

struct GlobalPollingView: View {
    @Environment(AppModel.self) private var model
    @State private var enabled: Bool?
    @State private var error: String?
    var body: some View {
        List {
            Section {
                LabeledContent("Automatische Ortung", value: enabled.map { $0 ? "Aktiv" : "Pausiert" } ?? "Wird geladen …")
                Text("Die Änderung gilt serverweit für automatische Abrufe aller Ortungsnetze.").font(.subheadline).foregroundStyle(.secondary)
            }
            if let enabled {
                NavigationLink(enabled ? "Automatik pausieren" : "Automatik fortsetzen") {
                    ManagementForm(title: enabled ? "Automatik pausieren" : "Automatik fortsetzen", path: "/api/mobile/v1/action", constants: ["action": .string("global_pause"), "paused": .bool(enabled)], confirmation: enabled ? "Alle automatischen Ortungsabrufe pausieren?" : "Automatische Ortungsabrufe wieder aktivieren?") { _ in self.enabled = !enabled; Task { await model.refresh() } }
                }
            }
            if let error { Text(error).foregroundStyle(.red) }
        }.navigationTitle("Automatische Ortung").navigationBarTitleDisplayMode(.inline)
        .task { await load() }.refreshable { await load() }
    }
    private func load() async { do { enabled = try await APIClient.shared.requestJSON(path: "/api/polling/settings")["polling"]["enabled"].boolValue; error = nil } catch { self.error = error.localizedDescription } }
}
