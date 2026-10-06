import SwiftUI
import UniformTypeIdentifiers
import SafariServices

struct ProviderSetupView: View {
    @Environment(AppModel.self) private var model
    @State private var status: JSONValue = .null
    @State private var error: String?
    var body: some View {
        List {
            Section {
                Label("Deine Netzwerke", systemImage: "point.3.connected.trianglepath.dotted").font(.title2.bold())
                Text("Accounts verbinden, Tracker importieren und mehrere Quellen als Fusion zusammenführen.").foregroundStyle(.secondary)
            }
            Section("Accounts & Import") {
                NavigationLink { AppleAccountSetupView() } label: { provider("Apple Account", "apple", "apple.logo") }
                NavigationLink { TrackerImportView(provider: "apple") } label: { Label("Apple-Tracker aus JSON importieren", systemImage: "square.and.arrow.down") }
                NavigationLink { GoogleSetupView() } label: { provider("Google Find Hub", "google", "network") }
                NavigationLink { SamsungSetupView() } label: { provider("Samsung SmartThings", "samsung", "tag.fill") }
            }
            Section("Objekte") {
                NavigationLink { FusionSetupView() } label: { Label("Fusionen einrichten", systemImage: "point.3.filled.connected.trianglepath.dotted") }
                NavigationLink { TrackerSourcesView() } label: { Label("Tracker entfernen & archivieren", systemImage: "archivebox") }
                Button { Task { await model.refresh(); await load() } } label: { Label("Alle Daten aktualisieren", systemImage: "arrow.clockwise") }
            }
            if let error { Section { Text(error).foregroundStyle(.red) } }
        }.rjListChrome().navigationTitle("Tracker einrichten").navigationBarTitleDisplayMode(.inline)
        .task { await load() }.refreshable { await load(); await model.refresh() }
    }
    private func provider(_ title: String, _ id: String, _ icon: String) -> some View {
        HStack { Label(title, systemImage: icon); Spacer(); Text(status[id]["connected"].boolValue == true ? "Verbunden" : "Einrichten").font(.caption).foregroundStyle(.secondary) }
    }
    private func load() async {
        do { status = try await APIClient.shared.requestJSON(path: "/api/v3/providers"); error = nil }
        catch { self.error = error.localizedDescription }
    }
}

struct AppleAccountSetupView: View {
    @Environment(AppModel.self) private var model
    @State private var email = ""
    @State private var password = ""
    @State private var code = ""
    @State private var methods: [String] = []
    @State private var selected = 0
    @State private var sent = false
    @State private var busy = false
    @State private var message = ""
    @State private var connected = false
    var body: some View {
        Form {
            Section("Apple Account") {
                Text("Verbinde deinen Apple Account für die Ortung importierter Tracker. Der Account ersetzt keine Tracker-JSON: Diese wird zusätzlich unter Import hinzugefügt.").font(.subheadline).foregroundStyle(.secondary)
                if methods.isEmpty {
                    TextField("Apple-ID / E-Mail", text: $email).textContentType(.username).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("Apple-Passwort", text: $password).textContentType(.password)
                    Button("Account verbinden") { Task { await login() } }.disabled(email.isEmpty || password.isEmpty || busy)
                } else {
                    Picker("Bestätigungsmethode", selection: $selected) { ForEach(Array(methods.enumerated()), id: \.offset) { i, name in Text(name).tag(i) } }
                    Button("Code anfordern") { Task { await send() } }.disabled(busy)
                    if sent {
                        TextField("Apple-Bestätigungscode", text: $code).textContentType(.oneTimeCode).keyboardType(.numberPad)
                        Button("Code bestätigen") { Task { await verify() } }.disabled(code.isEmpty || busy)
                    }
                }
            }
            if connected { Label("Apple Account verbunden", systemImage: "checkmark.shield.fill").foregroundStyle(.green) }
            if busy { ProgressView("Bitte warten …") }
            if !message.isEmpty { Text(message).textSelection(.enabled) }
            Section {
                NavigationLink("Apple-Tracker importieren") { TrackerImportView(provider: "apple") }
                NavigationLink("Apple Account abmelden") { ManagementForm(title: "Apple abmelden", path: "/api/apple/auth/logout", confirmation: "Apple Account auf dem Server abmelden?", destructive: true) { _ in Task { await model.refresh() } } }
            }
        }.rjListChrome().navigationTitle("Apple Account").navigationBarTitleDisplayMode(.inline)
    }
    private func login() async {
        busy = true; defer { busy = false }
        do {
            let value = try await APIClient.shared.requestJSON(path: "/api/login", method: "POST", json: ["email": email, "password": password])
            password = ""
            if value["status"].stringValue == "2fa" { methods = value["methods"].rows.compactMap(\.stringValue); message = "Bestätigungsmethode auswählen und Code anfordern." }
            else { connected = true; message = "Apple ist bereit."; await model.refresh() }
        } catch { message = error.localizedDescription }
    }
    private func send() async {
        busy = true; defer { busy = false }
        do { _ = try await APIClient.shared.requestJSON(path: "/api/2fa/request", method: "POST", json: ["index": selected]); sent = true; message = "Code angefordert." }
        catch { message = error.localizedDescription }
    }
    private func verify() async {
        busy = true; defer { busy = false }
        do { _ = try await APIClient.shared.requestJSON(path: "/api/2fa/submit", method: "POST", json: ["code": code]); code = ""; methods = []; sent = false; connected = true; message = "Apple verbunden."; await model.refresh() }
        catch { message = error.localizedDescription }
    }
}

struct TrackerImportView: View {
    let provider: String
    @Environment(AppModel.self) private var model
    @State private var name = ""
    @State private var content: Any?
    @State private var filename = ""
    @State private var choose = false
    @State private var busy = false
    @State private var replace = false
    @State private var confirm = false
    @State private var message = ""
    var body: some View {
        Form {
            Section(provider == "apple" ? "Apple-Tracker" : "Google-Zugang") {
                if provider == "apple" { TextField("Eindeutiger Trackername", text: $name).autocorrectionDisabled(); Toggle("Vorhandenen Tracker ausdrücklich ersetzen", isOn: $replace) }
                Button { choose = true } label: { Label(filename.isEmpty ? "JSON-Datei auswählen" : filename, systemImage: "doc.badge.plus") }
                Text(provider == "apple" ? "Kompatible FindMy-Accessory-JSON mit Tracker-Schlüsseln. Daten und Historie anderer Tracker bleiben erhalten." : "Wähle die secrets.json aus GoogleFindMyTools. Sie bleibt privat auf deinem Server.").font(.caption).foregroundStyle(.secondary)
                Button("Sicher importieren") { confirm = true }.disabled(content == nil || busy || (provider == "apple" && name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
            }
            if busy { ProgressView("Import läuft …") }
            if !message.isEmpty { Text(message).textSelection(.enabled) }
        }.rjListChrome().navigationTitle("JSON importieren").navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $choose, allowedContentTypes: [.json, .plainText], allowsMultipleSelection: false) { result in
            do {
                guard let url = try result.get().first else { return }
                let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                let values = try url.resourceValues(forKeys: [.fileSizeKey])
                guard (values.fileSize ?? 0) <= 1_048_576 else { throw APIError.message("Maximal 1 MB pro JSON-Datei.") }
                let data = try Data(contentsOf: url)
                let parsed = try JSONSerialization.jsonObject(with: data)
                guard parsed is [String: Any] || parsed is [Any] else { throw APIError.message("Die Datei enthält kein JSON-Objekt.") }
                content = parsed; filename = url.lastPathComponent
                if name.isEmpty { name = url.deletingPathExtension().lastPathComponent }
                message = "Datei bereit. Zum Import bestätigen."
            } catch { content = nil; message = error.localizedDescription }
        }
        .confirmationDialog(replace ? "Vorhandene Tracker-Schlüssel ersetzen?" : "Datei auf deinen Server importieren?", isPresented: $confirm, titleVisibility: .visible) { Button("Importieren", role: replace ? .destructive : nil) { Task { await upload() } } }
    }
    private func upload() async {
        guard let content else { return }; busy = true; defer { busy = false }
        do {
            let r = try await APIClient.shared.requestJSON(path: "/api/v3/import", method: "POST", json: ["provider": provider, "name": name, "content": content, "replace": replace])
            self.content = nil; filename = ""; message = r["message"].text
            Haptics.success(); await model.refresh()
        } catch { message = error.localizedDescription }
    }
}

struct GoogleSetupView: View {
    var body: some View {
        List {
            Section("Google Find Hub") {
                Text("Bestehende Google-Sitzungen werden übernommen. Neue Accounts werden über die GoogleFindMyTools-Secrets eingebunden.").foregroundStyle(.secondary)
                NavigationLink("Google secrets.json importieren") { TrackerImportView(provider: "google") }
                NavigationLink("Google-Werkzeuge herunterladen") { ManagementForm(title: "Werkzeuge einrichten", path: "/api/google/tools/download", explanation: "Lädt den festgelegten Upstream auf deinem Server.") }
                NavigationLink("Google-Bibliotheken einrichten") { ManagementForm(title: "Abhängigkeiten installieren", path: "/api/google/tools/dependencies") }
                NavigationLink("Geräte synchronisieren") { ManagementForm(title: "Geräte laden", path: "/api/google/devices/sync") }
                NavigationLink("Google-Zugang prüfen & reparieren") { GoogleRepairView() }
                NavigationLink("Google abmelden") { ManagementForm(title: "Google abmelden", path: "/api/google/secrets", method: "DELETE", confirmation: "Google-Zugang auf dem Server entfernen?", destructive: true) }
            }
        }.rjListChrome().navigationTitle("Google").navigationBarTitleDisplayMode(.inline)
    }
}

struct SamsungSetupView: View {
    @Environment(AppModel.self) private var model
    @State private var loginURL: URL?
    @State private var redirect = ""
    @State private var browser = false
    @State private var busy = false
    @State private var message = ""
    var body: some View {
        Form {
            Section("Samsung Account") {
                Text("Login vorbereiten, bei Samsung anmelden und die vollständige Rückleitungsadresse hier einfügen. Du kannst den Login-Link auch am Computer öffnen.").foregroundStyle(.secondary)
                Button("Samsung-Login vorbereiten") { Task { await start() } }.disabled(busy)
                if let loginURL {
                    Button("Bei Samsung anmelden") { browser = true }
                    ShareLink(item: loginURL) { Label("Login-Link kopieren oder teilen", systemImage: "square.and.arrow.up") }
                    Text("Der Link läuft nach 30 Minuten ab. Die Rückleitungsadresse enthält vertrauliche Anmeldedaten.").font(.caption).foregroundStyle(.secondary)
                }
                TextField("Vollständige Samsung-Rückleitungsadresse", text: $redirect, axis: .vertical).textInputAutocapitalization(.never).autocorrectionDisabled().privacySensitive()
                Button("Samsung verbinden & Geräte laden") { Task { await complete() } }.disabled(redirect.isEmpty || busy)
            }
            if busy { ProgressView("Bitte warten …") }
            if !message.isEmpty { Text(message).textSelection(.enabled) }
            Section {
                NavigationLink("Verschlüsselte Standorte: PIN hinterlegen") { ManagementForm(title: "Samsung-PIN speichern", path: "/api/samsung/pin", fields: [.init(id: "pin", label: "SmartThings Find PIN", kind: .secret, required: true)]) }
                NavigationLink("Samsung-Geräte synchronisieren") { ManagementForm(title: "Geräte laden", path: "/api/samsung/devices/sync") }
                NavigationLink("Samsung abmelden") { ManagementForm(title: "Samsung abmelden", path: "/api/samsung/auth/logout", confirmation: "Samsung Account vom Server abmelden?", destructive: true) }
            }
        }.rjListChrome().navigationTitle("Samsung").navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $browser) { if let loginURL { ServerSafariView(url: loginURL).ignoresSafeArea() } }
    }
    private func start() async {
        busy = true; defer { busy = false }
        do {
            let r = try await APIClient.shared.requestJSON(path: "/api/samsung/auth/start", method: "POST", json: [:])
            guard let text = r["login_url"].stringValue, let url = URL(string: text), url.scheme == "https" else { throw APIError.message("Samsung hat keinen gültigen HTTPS-Login-Link geliefert.") }
            loginURL = url; message = "Link bereit. Bei Samsung anmelden."
        } catch { message = error.localizedDescription }
    }
    private func complete() async {
        busy = true; defer { busy = false }
        do {
            let r = try await APIClient.shared.requestJSON(path: "/api/samsung/auth/complete", method: "POST", json: ["redirect_url": redirect.trimmingCharacters(in: .whitespacesAndNewlines)])
            redirect = ""; loginURL = nil; message = r["sync_warning"].stringValue ?? "Samsung verbunden. \(r["devices"].text) Geräte geladen."
            await model.refresh(); Haptics.success()
        } catch { message = error.localizedDescription }
    }
}

struct FusionSetupView: View {
    @Environment(AppModel.self) private var model
    @State private var apple = ""
    @State private var google = ""
    @State private var samsung = ""
    @State private var busy = false
    @State private var message = ""
    var body: some View {
        Form {
            Section("Quellen verbinden") {
                Text("Ein Apple-Tracker dient als Basis. Wähle eine Google- und/oder Samsung-Quelle für denselben Gegenstand.").font(.subheadline).foregroundStyle(.secondary)
                sourcePicker("Apple-Basis", provider: "apple", selection: $apple)
                sourcePicker("Google-Quelle", provider: "google", selection: $google)
                sourcePicker("Samsung-Quelle", provider: "samsung", selection: $samsung)
                Button("Fusion erstellen / ergänzen") { Task { await save() } }.disabled(apple.isEmpty || (google.isEmpty && samsung.isEmpty) || busy)
            }
            Section("Bestehende Fusionen") {
                ForEach(model.trackers.filter { $0.provider == "fusion" }) { tracker in
                    VStack(alignment: .leading) {
                        Text(tracker.name).font(.headline)
                        Text((tracker.linkedNetworks ?? []).joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                        NavigationLink("Google-Verknüpfung entfernen") { ManagementForm(title: "Google-Verknüpfung lösen", path: "/api/google/links/" + escaped(sourceID(tracker)), method: "DELETE", explanation: "Die einzelnen Tracker und ihre Historie bleiben erhalten.", confirmation: "Google aus dieser Fusion entfernen?", destructive: true) { _ in Task { await model.refresh() } } }
                        NavigationLink("Samsung-Verknüpfung entfernen") { ManagementForm(title: "Samsung-Verknüpfung lösen", path: "/api/samsung/links/" + escaped(sourceID(tracker)), method: "DELETE", explanation: "Die einzelnen Tracker und ihre Historie bleiben erhalten.", confirmation: "Samsung aus dieser Fusion entfernen?", destructive: true) { _ in Task { await model.refresh() } } }
                    }
                }
                if !model.trackers.contains(where: { $0.provider == "fusion" }) { Text("Noch keine Fusionen. Verbinde zuerst deine Quellen.").foregroundStyle(.secondary) }
            }
            if busy { ProgressView() }
            if !message.isEmpty { Text(message) }
        }.rjListChrome().navigationTitle("Fusionen").navigationBarTitleDisplayMode(.inline)
        .refreshable { await model.refresh() }
    }
    private func sourcePicker(_ title: String, provider: String, selection: Binding<String>) -> some View {
        Picker(title, selection: selection) { Text("Keine Auswahl").tag(""); ForEach(model.trackers.filter { $0.provider == provider }) { t in Text(t.name).tag(sourceID(t)) } }
    }
    private func save() async {
        busy = true; defer { busy = false }
        var completed: [String] = []
        do {
            if !google.isEmpty { _ = try await APIClient.shared.requestJSON(path: "/api/google/links", method: "POST", json: ["apple_name": apple, "google_id": google]); completed.append("Google") }
            if !samsung.isEmpty { _ = try await APIClient.shared.requestJSON(path: "/api/samsung/links", method: "POST", json: ["apple_name": apple, "samsung_id": samsung]); completed.append("Samsung") }
            message = "Fusion gespeichert: " + completed.joined(separator: " und "); Haptics.success()
        } catch { message = (completed.isEmpty ? "" : completed.joined(separator: ", ") + " bereits verbunden. ") + error.localizedDescription }
        await model.refresh()
    }
}

struct TrackerSourcesView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        List {
            Text("Apple-Tracker werden lokal entfernt. Google- und Samsung-Quellen werden archiviert und aus Fusionen gelöst; beim Anbieter werden keine Geräte gelöscht.").font(.caption).foregroundStyle(.secondary)
            ForEach(model.trackers.filter { ["apple", "google", "samsung"].contains($0.provider) }) { t in
                NavigationLink(t.name) { ManagementForm(title: t.provider == "apple" ? "Tracker entfernen" : "Quelle archivieren", path: "/api/v3/trackers/\(t.provider)/" + escaped(sourceID(t)), method: "DELETE", confirmation: "\(t.name) \(t.provider == "apple" ? "lokal entfernen" : "archivieren")?", destructive: true) { _ in Task { await model.refresh() } } }
            }
        }.rjListChrome().navigationTitle("Tracker verwalten").navigationBarTitleDisplayMode(.inline)
    }
}
func sourceID(_ tracker: Tracker) -> String {
    tracker.serverID ?? String(tracker.ref.dropFirst((tracker.ref.firstIndex(of: ":").map { tracker.ref.distance(from: tracker.ref.startIndex, to: $0) + 1 }) ?? 0))
}
func escaped(_ text: String) -> String {
    text.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#%"))) ?? text
}
