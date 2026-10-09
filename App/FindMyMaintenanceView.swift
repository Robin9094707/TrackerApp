import SwiftUI

struct FindMyMaintenanceView: View {
    @State private var state: JSONValue = .null
    @State private var password = ""
    @State private var code = ""
    @State private var busy = false
    @State private var confirm = false
    @State private var error: String?
    private var running: Bool { state["running"].boolValue == true }
    private var installed: String { state["installed_version"].text }
    private var latest: String { state["latest_version"].stringValue ?? "" }
    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    Image(systemName: "shippingbox.fill").font(.largeTitle).foregroundStyle(.blue)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Apple Find My").font(.title3.bold())
                        Text("FindMy.py · \(installed)").font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(.vertical, 8)
                Link("Originalprojekt ansehen", destination: URL(string: "https://github.com/malmeloo/FindMy.py")!)
                LabeledContent("Installiert", value: installed)
                if !latest.isEmpty { LabeledContent("Aktuelle stabile Version", value: latest) }
                if let runtime = state["runtime_version"].stringValue { LabeledContent("Im laufenden Server", value: runtime) }
                Button("Nach Update suchen", systemImage: "arrow.clockwise") { Task { await check() } }.disabled(busy || running)
            }
            Section("Update installieren") {
                Text("Das Paket kommt direkt von PyPI. Der Server prüft es zuerst isoliert gegen die vorhandenen Abhängigkeiten und sichert seine Daten. Bei einem Installationsfehler wird die vorherige Paketversion zurückgespielt.")
                    .font(.caption).foregroundStyle(.secondary)
                SecureField("Aktuelles Master-Passwort", text: $password).textContentType(.password)
                SecureField("2FA-/Wiederherstellungscode, falls aktiv", text: $code).textContentType(.oneTimeCode)
                Button("Geprüftes Update installieren", systemImage: "square.and.arrow.down") { confirm = true }
                    .disabled(busy || running || latest.isEmpty || latest == installed || password.isEmpty || state["can_update"].boolValue == false)
                if state["can_update"].boolValue == false {
                    Text("Starte den Server in einer eigenen Python-venv, um Paketupdates zu erlauben.").font(.caption).foregroundStyle(.orange)
                }
            }
            if running || !state["message"].text.isEmpty {
                Section("Fortschritt") {
                    if running { ProgressView("\(state["phase"].text) …") }
                    Text(state["message"].text)
                    if let backup = state["backup"].stringValue { Text("Sicherung: \(backup)").font(.caption).textSelection(.enabled) }
                    if state["restart_required"].boolValue == true {
                        Label("Serverdienst neu starten", systemImage: "arrow.trianglehead.2.clockwise.rotate.90").foregroundStyle(.orange)
                        Text("Nach dem Neustart wird die neue Version auch von allen laufenden Ortungsdiensten verwendet.").font(.caption)
                    }
                }
            }
            Section {
                NavigationLink { BackupsManagementView() } label: { Label("Sicherungen verwalten", systemImage: "externaldrive.badge.timemachine") }
                NavigationLink { GoogleRepairView() } label: { Label("Google-Werkzeuge verwalten", systemImage: "wrench.and.screwdriver") }
            }
            if let error { Text(error).foregroundStyle(.red) }
        }.rjListChrome().navigationTitle("FindMy.py verwalten").navigationBarTitleDisplayMode(.inline)
            .refreshable { await load() }
            .task {
                await load()
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(3)) } catch { break }
                    if running { await load() }
                }
            }
            .confirmationDialog("FindMy.py \(latest) installieren?", isPresented: $confirm, titleVisibility: .visible) {
                Button("Installieren") { Task { await update() } }
            } message: { Text("Der Server erstellt eine private Sicherung mit Zugangsdaten. Danach ist ein Neustart des Serverdienstes nötig.") }
    }
    private func load() async {
        do { state = try await APIClient.shared.requestJSON(path: "/api/server/findmy")["findmy"]; error = nil }
        catch { self.error = error.localizedDescription }
    }
    private func check() async {
        busy = true; defer { busy = false }
        do { _ = try await APIClient.shared.requestJSON(path: "/api/server/findmy", method: "POST", json: ["action": "check"]); await load() }
        catch { self.error = error.localizedDescription }
    }
    private func update() async {
        busy = true; defer { busy = false; password = ""; code = "" }
        do {
            _ = try await APIClient.shared.requestJSON(path: "/api/server/findmy", method: "POST", json: ["action": "update", "confirmed": true, "version": latest, "current_password": password, "current_code": code])
            await load()
        } catch { self.error = error.localizedDescription }
    }
}
