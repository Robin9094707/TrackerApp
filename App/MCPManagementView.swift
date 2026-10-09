import SwiftUI

struct MCPManagementView: View {
    @State private var mcp: JSONValue = .null
    @State private var connections: [JSONValue] = []
    @State private var audit: [JSONValue] = []
    @State private var enabled = false
    @State private var actions = false
    @State private var guests = true
    @State private var base = ""
    @State private var busy = false
    @State private var error: String?
    @State private var diagnostic: JSONValue?
    @State private var revokeID: String?
    @State private var confirmRevoke = false
    @State private var confirmSave = false
    @State private var showSetup = false
    private var endpoint: String { mcp["endpoint"].stringValue ?? "" }

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    Image(systemName: "bubble.left.and.text.bubble.right.fill").font(.largeTitle).foregroundStyle(.blue)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("ChatGPT verbinden").font(.title3.bold())
                        Label(mcp["ready"].boolValue == true ? "Bereit für ChatGPT" : "Einrichtung prüfen",
                              systemImage: mcp["ready"].boolValue == true ? "checkmark.circle.fill" : "exclamationmark.circle")
                            .font(.caption).foregroundStyle(mcp["ready"].boolValue == true ? Color.green : Color.orange)
                    }
                }.padding(.vertical, 8)
                if !endpoint.isEmpty {
                    Text(endpoint).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    ShareLink(item: endpoint) { Label("MCP-Link kopieren oder teilen", systemImage: "square.and.arrow.up") }
                }
                Button("In ChatGPT einrichten", systemImage: "link.badge.plus") { showSetup = true }
                Button("Konfiguration prüfen", systemImage: "stethoscope") { Task { await check() } }
                NavigationLink { MCPToolCatalogView() } label: { Label("Verfügbare ChatGPT-Tools", systemImage: "square.grid.2x2") }
            }
            Section("Server & Berechtigungen") {
                TextField("Öffentliche HTTPS-Basisadresse", text: $base).keyboardType(.URL)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                Toggle("MCP-Server aktiv", isOn: $enabled)
                Toggle("Bestätigte Besitzeraktionen", isOn: $actions)
                Toggle("Zugriff mit Freigabelinks", isOn: $guests)
                Text("Eine neue Basisadresse oder das Ein-/Ausschalten widerruft bestehende MCP-Verbindungen. Danach in ChatGPT erneut anmelden.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Einstellungen speichern") { confirmSave = true }
            }
            if let diagnostic {
                Section("Prüfergebnis") {
                    ForEach(Array(diagnostic["checks"].rows.enumerated()), id: \.offset) { _, check in
                        Label(check["label"].text, systemImage: check["ok"].boolValue == true ? "checkmark.circle.fill" : "exclamationmark.circle")
                            .foregroundStyle(check["ok"].boolValue == true ? Color.green : Color.orange)
                        if check["ok"].boolValue != true { Text(check["detail"].text).font(.caption) }
                    }
                    Text(diagnostic["note"].text).font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Aktive OAuth-Verbindungen (\(connections.count))") {
                if connections.isEmpty { Text("Noch keine aktive Verbindung. Mit dem MCP-Link in ChatGPT verbinden.").foregroundStyle(.secondary) }
                ForEach(connections, id: \.identifier) { connection in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(connection["client_name"].text).font(.headline)
                            Spacer()
                            Text(connection["principal"].text == "guest" ? "Freigabe" : "Besitzer").font(.caption).foregroundStyle(.secondary)
                        }
                        if let ts = connection["last_used_ts"].numberValue, ts > 0 {
                            Text("Zuletzt genutzt: " + Date(timeIntervalSince1970: ts).rjTimelineText).font(.caption).foregroundStyle(.secondary)
                        }
                        if let ts = connection["expires_ts"].numberValue {
                            Text("Gültig bis: " + Date(timeIntervalSince1970: ts).rjTimelineText).font(.caption).foregroundStyle(.secondary)
                        }
                        Text("Berechtigungen: " + connection["scopes"].rows.map(\.text).joined(separator: ", ")).font(.caption).foregroundStyle(.secondary)
                        Button("Verbindung widerrufen", role: .destructive) { revokeID = connection.identifier; confirmRevoke = true }
                    }.padding(.vertical, 4)
                }
                Button("Alle widerrufen / neu verbinden", role: .destructive) { revokeID = nil; confirmRevoke = true }
                    .disabled(connections.isEmpty)
                Text("OAuth-Verbindungen sind autorisierte Zugriffe, keine dauerhaft geöffneten Netzwerkverbindungen. Widerruf sperrt auch die zugehörigen Refresh-Tokens.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Sicherheit & Zugriffe") {
                NavigationLink { SecurityManagementView() } label: { Label("Master-Passwort & Zwei-Faktor-Schutz", systemImage: "lock.shield") }
                NavigationLink { ClientAccessView() } label: { Label("App-Geräte & API-Schlüssel", systemImage: "key.horizontal") }
                if let ts = mcp["last_call_ts"].numberValue, ts > 0 { LabeledContent("Letzter MCP-Aufruf", value: Date(timeIntervalSince1970: ts).rjTimelineText) }
                if let lastError = mcp["last_error"].stringValue, !lastError.isEmpty { Text(lastError).foregroundStyle(.orange) }
                DisclosureGroup("Letzte MCP-Ereignisse") {
                    ForEach(Array(audit.enumerated()), id: \.offset) { _, row in
                        ManagementRows(value: row)
                    }
                }
            }
            if busy { ProgressView("Wird aktualisiert …") }
            if let error { Text(error).foregroundStyle(.red) }
        }.rjListChrome().navigationTitle("ChatGPT / MCP").navigationBarTitleDisplayMode(.inline)
            .disabled(busy)
            .task { await load() }.refreshable { await load() }
            .confirmationDialog("MCP-Einstellungen speichern?", isPresented: $confirmSave, titleVisibility: .visible) {
                Button("Speichern") { Task { await save() } }
            }
            .confirmationDialog(revokeID == nil ? "Alle ChatGPT-Verbindungen sofort sperren?" : "Diese ChatGPT-Verbindung sofort sperren?", isPresented: $confirmRevoke, titleVisibility: .visible) {
                Button("Widerrufen", role: .destructive) { Task { await revoke() } }
            } message: { Text("Zum erneuten Zugriff den MCP-Link in ChatGPT verbinden und auf der Server-Anmeldeseite authentifizieren.") }
            .sheet(isPresented: $showSetup) {
                NavigationStack {
                    List {
                        Section("MCP-Link") {
                            Text(endpoint).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                            ShareLink(item: endpoint) { Label("Link kopieren", systemImage: "doc.on.doc") }
                        }
                        Section("Mit ChatGPT verbinden") {
                            Text("1. Öffne in ChatGPT die Verwaltung für Apps bzw. eigene MCP-Verbindungen.")
                            Text("2. Lege eine Verbindung mit dem MCP-Link an. Verwende OAuth als Anmeldung.")
                            Text("3. ChatGPT öffnet die Anmeldeseite deines Servers. Gib dort dein Master-/Kontopasswort und gegebenenfalls deinen 2FA-Code ein.")
                            Text("4. Bestätige den Zugriff und kehre zu ChatGPT zurück.")
                            Text("Eine widerrufene Verbindung bei Bedarf zuerst aus ChatGPT entfernen und neu hinzufügen. Die App kann eine Verbindung auf dem Server sperren; die Einrichtung in ChatGPT erfolgt dort.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }.rjListChrome().navigationTitle("Verbindung einrichten").navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { showSetup = false } } }
                }.presentationDetents([.large])
            }
    }
    private func load() async {
        busy = true; defer { busy = false }
        do {
            let response = try await APIClient.shared.requestJSON(path: "/api/mcp/settings")
            mcp = response["mcp"]; connections = response["connections"].rows; audit = response["audit"].rows
            enabled = mcp["enabled"].boolValue ?? false; actions = mcp["allow_actions"].boolValue ?? false
            guests = mcp["allow_shared_access"].boolValue ?? true; base = mcp["public_base_url"].stringValue ?? ""
            error = nil
        } catch { self.error = error.localizedDescription }
    }
    private func save() async {
        busy = true
        do {
            _ = try await APIClient.shared.requestJSON(path: "/api/mcp/settings", method: "POST", json: ["enabled": enabled, "allow_actions": actions, "allow_shared_access": guests, "public_base_url": base])
            busy = false; await load(); diagnostic = nil
        } catch { self.error = error.localizedDescription; busy = false }
    }
    private func check() async {
        busy = true; defer { busy = false }
        do { diagnostic = try await APIClient.shared.requestJSON(path: "/api/mcp/diagnostics"); error = nil }
        catch { self.error = error.localizedDescription }
    }
    private func revoke() async {
        busy = true
        do {
            let path = revokeID.map { "/api/mcp/connections/" + escaped($0) } ?? "/api/mcp/settings"
            _ = try await APIClient.shared.requestJSON(path: path, method: "DELETE", json: [:])
            busy = false; await load()
        } catch { self.error = error.localizedDescription; busy = false }
    }
}
