import SwiftUI

struct BarkConfiguration: Decodable {
    var enabled: Bool
    var server: String
    var batch: Bool
    var group: String
    var deviceCount: Int
    var globalEnabled: Bool
    enum CodingKeys: String, CodingKey {
        case enabled, server, batch, group
        case deviceCount = "device_count", globalEnabled = "global_enabled"
    }
}

struct BarkSettingsView: View {
    @State private var server = "https://api.day.app"
    @State private var enabled = false
    @State private var batch = false
    @State private var group = "RJ Tracker"
    @State private var keys = ""
    @State private var count = 0
    @State private var globalEnabled = true
    @State private var loaded = false
    @State private var busy = false
    @State private var error: String?
    @State private var message: String?
    @State private var title = "RJ Tracker"
    @State private var bodyText = ""
    @State private var confirmSend = false
    @State private var confirmReset = false
    private let path = "/api/mobile/v1/bark"
    var body: some View {
        Form {
            Section {
                Label("Mitteilungen auch bei geschlossener Tracker-App", systemImage: "bell.badge.fill").font(.headline)
                Text("Installiere Bark auf deinem iPhone. Trage unten den Geräteschlüssel aus Bark ein. Dein Tracker-Server übernimmt den Versand.")
                    .foregroundStyle(.secondary)
                if !globalEnabled { Label("Die globalen Benachrichtigungen sind auf dem Server ausgeschaltet.", systemImage: "pause.circle").foregroundStyle(.orange) }
            }
            Section("Verbindung") {
                Toggle("Bark aktiv", isOn: $enabled)
                TextField("Bark-Server", text: $server).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                TextField("Gruppe in Bark", text: $group)
                LabeledContent("Gespeicherte Empfänger", value: "\(count)")
                Text("Geräteschlüssel · einer pro Zeile").font(.subheadline)
                TextEditor(text: $keys).font(.system(.footnote, design: .monospaced))
                    .frame(minHeight: 90).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .privacySensitive().accessibilityLabel("Bark-Geräteschlüssel")
                Text("Neue Einträge ersetzen die Empfängerliste. Leer lassen behält die gespeicherten Schlüssel. Maximal 50 Empfänger; keine vollständigen Bark-URLs einfügen.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Server unterstützt Batch-API", isOn: $batch)
                Text("Standardmäßig bekommt jeder Empfänger einen eigenen Aufruf. Batch nur für einen Bark-Server aktivieren, der device_keys unterstützt (ab bark-server 2.1.9).")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Einstellungen sichern") { Task { await save() } }.disabled(!loaded || busy)
            }
            Section {
                TextField("Titel", text: $title)
                TextField("Nachricht an alle gespeicherten Empfänger", text: $bodyText, axis: .vertical).lineLimit(3...8)
                Button("Sammelmeldung senden", systemImage: "paperplane.fill") { confirmSend = true }
                    .disabled(busy || !enabled || count == 0 || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || title.count > 100 || bodyText.count > 900)
                Text("Verwendet die zuletzt gesicherte Empfängerliste. Zustellversuche stehen unter Meldungen. Ruhezeiten gelten auch hier.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: { Text("Sammelmeldung") }
            if let message { Section { Label(message, systemImage: "checkmark.circle").foregroundStyle(Color.accentColor) } }
            if let error { Section { Text(error).foregroundStyle(.red); Button("Erneut laden") { Task { await load() } } } }
            if busy { ProgressView() }
            if loaded && count > 0 {
                Section { Button("Bark-Verbindung entfernen", role: .destructive) { confirmReset = true } }
            }
        }
        .rjFormChrome().navigationTitle("Bark & Sammelmeldungen").navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .disabled(busy)
        .confirmationDialog("Nachricht an \(count) Bark-Empfänger senden?", isPresented: $confirmSend, titleVisibility: .visible) {
            Button("Jetzt senden") { Task { await send() } }
        } message: { Text("\(title)\n\(bodyText)") }
        .confirmationDialog("Alle Bark-Schlüssel entfernen?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Entfernen", role: .destructive) { Task { await reset() } }
        }
    }
    @MainActor private func apply(_ value: BarkConfiguration) {
        enabled = value.enabled; server = value.server; batch = value.batch; group = value.group
        count = value.deviceCount; globalEnabled = value.globalEnabled; loaded = true; keys = ""
    }
    @MainActor private func load() async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do { let value: BarkConfiguration = try await APIClient.shared.request(path: path); apply(value); error = nil }
        catch { self.error = error.localizedDescription }
    }
    @MainActor private func save() async {
        guard !busy else { return }; busy = true; defer { busy = false }
        var json: [String: Any] = ["enabled": enabled, "server": server, "batch": batch, "group": group]
        let newKeys = keys.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        if !newKeys.isEmpty { json["device_keys"] = newKeys }
        do {
            let value: BarkConfiguration = try await APIClient.shared.request(path: path, method: "PUT", json: json)
            apply(value); message = "Bark-Einstellungen gesichert."; error = nil
        } catch { self.error = error.localizedDescription }
    }
    @MainActor private func send() async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do {
            let _: JSONValue = try await APIClient.shared.request(path: path + "/bulk", method: "POST", json: ["title": title, "body": bodyText])
            message = "Sammelmeldung eingereiht. Zustellstatus unter Meldungen prüfen."; bodyText = ""; error = nil
        } catch { self.error = error.localizedDescription }
    }
    @MainActor private func reset() async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do { let value: BarkConfiguration = try await APIClient.shared.request(path: path, method: "DELETE"); apply(value); message = "Bark-Verbindung entfernt."; error = nil }
        catch { self.error = error.localizedDescription }
    }
}
