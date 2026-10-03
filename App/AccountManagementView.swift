import SwiftUI

struct AccountManagementView: View {
    @Environment(AppModel.self) private var model
    @State private var user: JSONValue = .null
    @State private var error: String?
    var body: some View {
        List {
            Section("Profil") {
                LabeledContent("Benutzername", value: user["username"].text)
                LabeledContent("Anzeigename", value: user["display_name"].text)
                NavigationLink("Profil bearbeiten") {
                    ManagementForm(title: "Profil speichern", path: "/api/account/profile", method: "PATCH", fields: [.init(id: "display_name", label: "Anzeigename", required: true), .init(id: "email", label: "E-Mail-Adresse")], initial: ["display_name": user["display_name"], "email": user["email"]]) { user = $0["user"]; Task { await model.refresh() } }
                }.disabled(user.objectValue == nil)
            }
            NavigationLink("Passwort, 2FA & Passkeys") { SecurityManagementView() }
            if user["is_main_admin"].boolValue == true || model.bootstrap?.session?.user?.isMainAdmin == true {
                NavigationLink("Benutzer verwalten") { UsersManagementView() }
            }
            if let error { Text(error).foregroundStyle(.red) }
        }.scrollContentBackground(.hidden).rjScreenChrome().navigationTitle("Konto & Sicherheit").navigationBarTitleDisplayMode(.inline)
        .task { await load() }.refreshable { await load() }
    }
    private func load() async { do { user = try await APIClient.shared.requestJSON(path: "/api/account/profile")["user"]; error = nil } catch { self.error = error.localizedDescription } }
}

struct UsersManagementView: View {
    @State private var users: [JSONValue] = []
    @State private var error: String?
    var body: some View {
        List {
            NavigationLink("Benutzer erstellen") { UserEditorView() }
            ForEach(users, id: \.identifier) { user in
                NavigationLink { UserEditorView(user: user) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(user["display_name"].text).font(.headline)
                        Text("\(user["username"].text) · \(user["active"].boolValue == false ? "Deaktiviert" : "Aktiv")").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if let error { Text(error).foregroundStyle(.red) }
        }.scrollContentBackground(.hidden).rjScreenChrome().navigationTitle("Benutzer").navigationBarTitleDisplayMode(.inline)
        .task { await load() }.refreshable { await load() }
    }
    private func load() async { do { users = try await APIClient.shared.requestJSON(path: "/api/admin/users")["users"].rows; error = nil } catch { self.error = error.localizedDescription } }
}
struct UserEditorView: View {
    var user: JSONValue = .null
    private var existing: Bool { !user.identifier.isEmpty }
    private var path: String { "/api/admin/users" + (existing ? "/\(user.identifier)" : "") }
    var body: some View {
        List {
            NavigationLink(existing ? "Benutzerdaten bearbeiten" : "Neues Konto anlegen") {
                ManagementForm(title: existing ? "Benutzer speichern" : "Benutzer erstellen", path: path, method: existing ? "PATCH" : "POST", fields: [
                    .init(id: "username", label: "Benutzername", required: true), .init(id: "display_name", label: "Anzeigename", required: true), .init(id: "email", label: "E-Mail-Adresse")
                ] + (existing ? [] : [.init(id: "password", label: "Startpasswort · mindestens 10 Zeichen", kind: .secret, required: true, minimum: 10)]), initial: user.objectValue.map { values in values.filter { ["username", "display_name", "email"].contains($0.key) } } ?? [:])
            }
            if existing {
                NavigationLink("Passwort zurücksetzen") { ManagementForm(title: "Passwort zurücksetzen", path: path, method: "PATCH", fields: [.init(id: "new_password", label: "Neues Passwort · mindestens 10 Zeichen", kind: .secret, required: true, minimum: 10)], confirmation: "Das Passwort dieses Benutzers ersetzen?") }
                if user.identifier != "main" {
                    NavigationLink("Kontozugang ändern") { ManagementForm(title: "Zugang speichern", path: path, method: "PATCH", fields: [.init(id: "active", label: "Anmeldung erlaubt", kind: .toggle)], initial: ["active": user["active"]]) }
                    NavigationLink("2FA zurücksetzen") { ManagementForm(title: "2FA zurücksetzen", path: path + "/2fa/reset", constants: ["confirmed": .bool(true)], confirmation: "Zwei-Faktor-Schutz dieses Benutzers entfernen?", destructive: true) }
                    NavigationLink("Alle Passkeys entfernen") { ManagementForm(title: "Passkeys entfernen", path: path + "/passkeys/reset", constants: ["confirmed": .bool(true)], confirmation: "Alle Passkeys dieses Benutzers entfernen?", destructive: true) }
                    NavigationLink("Benutzer endgültig löschen") { ManagementForm(title: "Benutzer löschen", path: path, method: "DELETE", constants: ["confirmed": .bool(true), "username": user["username"]], explanation: "Konto und private Tracker-Daten von \(user["username"].text) werden endgültig gelöscht.", confirmation: "\(user["username"].text) und sämtliche privaten Daten endgültig löschen?", destructive: true) }
                }
            }
        }.scrollContentBackground(.hidden).rjScreenChrome().navigationTitle(existing ? user["username"].text : "Neuer Benutzer").navigationBarTitleDisplayMode(.inline)
    }
}

