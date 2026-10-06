import SwiftUI

struct ClientAccessView: View {
    @State private var clients: [JSONValue] = []
    @State private var keys: [JSONValue] = []
    @State private var current = ""
    @State private var error: String?
    var body: some View {
        List {
            Section("Skripte & weitere Apps") {
                NavigationLink { APIKeyCreateView() } label: { Label("API-Schlüssel erstellen", systemImage: "key.horizontal") }
                Text("Schlüssel sind an dein Konto gebunden, zeitlich begrenzt und einzeln widerrufbar.").font(.caption).foregroundStyle(.secondary)
                ForEach(keys, id: \.identifier) { key in
                    Section(key["label"].text) {
                        Text(key["scopes"].rows.map(\.text).joined(separator: " · ")).font(.caption)
                        Text(key["revoked"].boolValue == true ? "Widerrufen" : "Aktiv").foregroundStyle(.secondary)
                        if key["revoked"].boolValue != true {
                            NavigationLink("Schlüssel widerrufen") { ManagementForm(title: "API-Schlüssel widerrufen", path: "/api/v3/keys/" + escaped(key.identifier), method: "DELETE", confirmation: "Zugriff dieses Skripts sofort sperren?", destructive: true) { _ in Task { await load() } } }
                        }
                    }
                }
            }
            Section("Angemeldete Geräte") {
                ForEach(clients, id: \.identifier) { client in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(client["label"].text).font(.headline)
                        Text(client.identifier == current ? "Dieses Gerät" : client["revoked"].boolValue == true ? "Abgemeldet" : "Aktiv").font(.caption).foregroundStyle(.secondary)
                        if client["revoked"].boolValue != true {
                            NavigationLink("Gerät abmelden") { ManagementForm(title: "Gerät abmelden", path: "/api/v3/clients/" + escaped(client.identifier), method: "DELETE", confirmation: "Diese Sitzung sofort abmelden?", destructive: true) { _ in Task { await load() } } }
                        }
                    }
                }
            }
            if let error { Text(error).foregroundStyle(.red) }
        }.rjListChrome().navigationTitle("Geräte & API-Schlüssel").navigationBarTitleDisplayMode(.inline)
        .task { await load() }.refreshable { await load() }
    }
    private func load() async {
        do {
            let c = try await APIClient.shared.requestJSON(path: "/api/v3/clients")
            let k = try await APIClient.shared.requestJSON(path: "/api/v3/keys")
            clients = c["clients"].rows; current = c["current_client_id"].text; keys = k["keys"].rows; error = nil
        } catch { self.error = error.localizedDescription }
    }
}

struct APIKeyCreateView: View {
    @State private var name = ""
    @State private var password = ""
    @State private var code = ""
    @State private var read = true
    @State private var locate = false
    @State private var manage = false
    @State private var days = 90
    @State private var token = ""
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        Form {
            if token.isEmpty {
                Section("Zugriff festlegen") {
                    TextField("Name, z. B. Windows-Skript", text: $name)
                    Toggle("Tracker & Historie lesen", isOn: $read)
                    Toggle("Ortung auslösen", isOn: $locate)
                    Toggle("Tracker-Details bearbeiten", isOn: $manage)
                    Stepper("Gültigkeit: \(days) Tage", value: $days, in: 1...365)
                }
                Section("Identität bestätigen") {
                    SecureField("Aktuelles Kontopasswort", text: $password).textContentType(.password)
                    SecureField("2FA-Code, falls aktiviert", text: $code)
                    Button("Schlüssel erstellen") { Task { await create() } }.disabled(busy || name.isEmpty || password.isEmpty || (!read && !locate && !manage))
                }
            } else {
                Section("Jetzt sicher speichern") {
                    Text("Dieser Schlüssel wird nur einmal angezeigt. Er erlaubt ausschließlich die gewählten Aktionen.").foregroundStyle(.orange)
                    Text(token).font(.system(.caption, design: .monospaced)).textSelection(.enabled).privacySensitive()
                    ShareLink(item: token) { Label("Schlüssel sichern", systemImage: "square.and.arrow.up") }
                    Text("HTTP-Header: Authorization: Bearer <Schlüssel>").font(.caption)
                }
            }
            if busy { ProgressView() }
            if let error { Text(error).foregroundStyle(.red) }
        }.rjListChrome().navigationTitle("API-Schlüssel").navigationBarTitleDisplayMode(.inline)
    }
    private func create() async {
        busy = true; defer { busy = false }
        do {
            var scopes: [String] = []; if read { scopes.append("read") }; if locate { scopes.append("locate") }; if manage { scopes.append("manage") }
            let r = try await APIClient.shared.requestJSON(path: "/api/v3/keys", method: "POST", json: ["label": name, "scopes": scopes, "expires_days": days, "current_password": password, "current_code": code])
            guard let value = r["token"].stringValue else { throw APIError.message("Server hat keinen Schlüssel geliefert.") }
            token = value; password = ""; code = ""; error = nil; Haptics.success()
        } catch { self.error = error.localizedDescription }
    }
}
