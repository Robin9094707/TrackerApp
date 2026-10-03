import SwiftUI

struct BackupsManagementView: View {
    @Environment(AppModel.self) private var model
    @State private var backups: [JSONValue] = []
    @State private var error: String?
    @State private var downloading = false
    @State private var file: URL?
    var body: some View {
        List {
            NavigationLink("Sicherung erstellen") {
                ManagementForm(title: "Backup erstellen", path: "/api/v2/backups", fields: [.init(id: "include_history", label: "Standortverläufe einschließen", kind: .toggle), .init(id: "include_secrets", label: "Provider-Zugangsdaten einschließen", kind: .toggle)], explanation: "Sicherungen bleiben zunächst auf deinem Server. Backups mit Zugangsdaten enthalten vertrauliche Informationen.")
            }
            if downloading { ProgressView("Backup herunterladen …") }
            if let file { ShareLink(item: file) { Label("Heruntergeladenes Backup sichern", systemImage: "square.and.arrow.up") } }
            ForEach(backups, id: \.identifier) { backup in
                Section {
                    Text(backup["name"].text).font(.headline).textSelection(.enabled)
                    LabeledContent("Größe", value: ByteCountFormatter.string(fromByteCount: Int64(backup["size"].integer), countStyle: .file))
                    Button("Herunterladen") { Task { await download(backup.identifier) } }.disabled(downloading)
                    NavigationLink("Wiederherstellen") {
                        ManagementForm(title: "Backup wiederherstellen", path: "/api/v2/backups/\(backup.identifier)/restore", explanation: "Aktuelle Serverdaten werden durch diese Sicherung ersetzt. Der Server erstellt vorher automatisch ein Backup des jetzigen Zustands.", confirmation: "\(backup.identifier) wiederherstellen und aktuelle Daten ersetzen?", destructive: true) { _ in APIClient.shared.clearHistoryCache(); Task { await model.refresh() } }
                    }
                    NavigationLink("Backup löschen") { ManagementForm(title: "Backup löschen", path: "/api/v2/backups/\(backup.identifier)", method: "DELETE", confirmation: "Diese Sicherung endgültig löschen?", destructive: true) }
                }
            }
            if let error { Text(error).foregroundStyle(.red) }
        }.scrollContentBackground(.hidden).rjScreenChrome().navigationTitle("Backups").navigationBarTitleDisplayMode(.inline)
        .task { await load() }.refreshable { await load() }
    }
    private func load() async { do { backups = try await APIClient.shared.requestJSON(path: "/api/v2/backups")["backups"].rows; error = nil } catch { self.error = error.localizedDescription } }
    private func download(_ name: String) async {
        downloading = true; defer { downloading = false }
        do { file = try await APIClient.shared.downloadBackup(name: name); error = nil } catch { self.error = error.localizedDescription }
    }
}

struct GoogleRepairView: View {
    @State private var runtime: JSONValue = .null
    @State private var message: String?
    @State private var error: String?
    @State private var busy = false
    @State private var operation: String?
    var body: some View {
        List {
            Section("Google-Netzwerk") {
                LabeledContent("Bereit", value: runtime["ready"].text)
                LabeledContent("Werkzeuge installiert", value: runtime["tools_installed"].text)
                LabeledContent("Zugang vorhanden", value: runtime["secrets_uploaded"].text)
                if let text = runtime["error"].stringValue, !text.isEmpty { Text(text).foregroundStyle(.secondary) }
            }
            Section {
                Button("Google-Reparatur starten") { operation = "repair" }.disabled(busy)
                Button("Zugangsdaten neu einlesen") { operation = "reload-secrets" }.disabled(busy)
                Text("Die Reparatur läuft auf dem Server weiter. Falls eine neue Google-Anmeldung nötig ist, wird sie hierdurch nicht ersetzt.").font(.caption).foregroundStyle(.secondary)
            }
            if busy { ProgressView() }
            if let message { Text(message) }
            if let error { Text(error).foregroundStyle(.red) }
            DisclosureGroup("Weitere Statusdetails") { ManagementRows(value: runtime["guardian"]) }
        }.scrollContentBackground(.hidden).rjScreenChrome().navigationTitle("Google-Reparatur").navigationBarTitleDisplayMode(.inline)
        .task { await load() }.refreshable { await load() }
        .confirmationDialog("Google-Zugang auf dem Server prüfen bzw. neu laden?", isPresented: Binding(get: { operation != nil }, set: { if !$0 { operation = nil } }), titleVisibility: .visible) {
            if let operation { Button("Ausführen") { Task { await run(operation) } } }
        }
    }
    private func load() async { do { runtime = try await APIClient.shared.requestJSON(path: "/api/google/guardian/status")["runtime"]; error = nil } catch { self.error = error.localizedDescription } }
    private func run(_ operation: String) async {
        busy = true; defer { busy = false }
        do { let result = try await APIClient.shared.requestJSON(path: "/api/google/guardian/\(operation)", method: "POST", json: [:]); message = result["message"].stringValue ?? "Zugangsdaten neu eingelesen."; await load() } catch { self.error = error.localizedDescription }
    }
}

struct StorageCleanupView: View {
    @State private var storage: JSONValue = .null
    @State private var selected: Set<String> = []
    @State private var preview: JSONValue?
    @State private var error: String?
    @State private var busy = false
    @State private var confirm = false
    @State private var receipt: String?
    var body: some View {
        List {
            Section { Text("Wähle Kategorien und prüfe zuerst die Servervorschau. Erst nach deiner Bestätigung werden Daten entfernt.").foregroundStyle(.secondary) }
            ForEach(storage["cleanup"].rows, id: \.identifier) { item in
                Toggle(isOn: Binding(get: { selected.contains(item.identifier) }, set: { value in
                    if value { selected.insert(item.identifier) } else { selected.remove(item.identifier) }; preview = nil
                })) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item["label"].text)
                        Text(item["description"].stringValue ?? "").font(.caption).foregroundStyle(.secondary)
                        if let reason = item["blocked_reason"].stringValue, !reason.isEmpty { Text(reason).font(.caption).foregroundStyle(.orange) }
                    }
                }.disabled(item["available"].boolValue != true || busy)
            }
            Button("Vorschau berechnen") { Task { await prepare() } }.disabled(selected.isEmpty || busy)
            if let preview {
                Section("Vorschau") {
                    ManagementRows(value: .object((preview.objectValue ?? [:]).filter { !["preview_token", "token"].contains($0.key) }))
                    Button("Auswahl bereinigen", role: .destructive) { confirm = true }.disabled(busy || preview["preview_token"].stringValue == nil)
                }
            }
            if busy { ProgressView("Server arbeitet …") }
            if let receipt { Text(receipt).foregroundStyle(.green) }
            if let error { Text(error).foregroundStyle(.red) }
        }.scrollContentBackground(.hidden).rjScreenChrome().navigationTitle("Speicher bereinigen").navigationBarTitleDisplayMode(.inline)
        .task { await load() }.refreshable { if !busy { await load() } }
        .confirmationDialog("Die in der Vorschau ausgewählten Daten endgültig entfernen?", isPresented: $confirm, titleVisibility: .visible) { Button("Bereinigen", role: .destructive) { Task { await execute() } } }
    }
    private func load() async { do { storage = try await APIClient.shared.requestJSON(path: "/api/v2/storage"); preview = nil; error = nil } catch { self.error = error.localizedDescription } }
    private func prepare() async {
        busy = true; defer { busy = false }; error = nil
        do { preview = try await APIClient.shared.requestJSON(path: "/api/v2/storage/cleanup/preview", method: "POST", json: ["targets": selected.sorted()]) } catch { self.error = error.localizedDescription }
    }
    private func execute() async {
        guard let token = preview?["preview_token"].stringValue else { return }
        busy = true; defer { busy = false }; error = nil
        do {
            let result = try await APIClient.shared.requestJSON(path: "/api/v2/storage/cleanup", method: "POST", json: ["targets": selected.sorted(), "preview_token": token, "confirmed": true])
            receipt = result["status"].stringValue == "partial" ? "Teilweise bereinigt. Bitte Serverergebnis und Speicher erneut prüfen." : "Bereinigung abgeschlossen."
            preview = nil; selected = []; await load()
        } catch { preview = nil; self.error = error.localizedDescription }
    }
}

