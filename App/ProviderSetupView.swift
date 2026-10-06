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
    @State private var file: JSONImportFile?
    @State private var text = ""
    @State private var localName = ""
    @State private var source = 0
    @State private var localFiles: [LocalImportFile] = []
    @State private var choose = false
    @State private var busy = false
    @State private var reading = false
    @State private var replace = false
    @State private var confirm = false
    @State private var message = ""
    @State private var failed = false

    private var unavailable: Bool { busy || reading }
    var body: some View {
        Form {
            Section {
                Label(provider == "apple" ? "Apple-Tracker hinzufügen" : "Google-Zugang einrichten", systemImage: "doc.badge.plus").font(.headline)
                Text(provider == "apple" ? "Kompatible FindMy-Accessory-JSON mit Tracker-Schlüsseln importieren." : "Die secrets.json aus GoogleFindMyTools importieren.").font(.subheadline).foregroundStyle(.secondary)
                Picker("Importquelle", selection: $source) {
                    Text("Datei").tag(0); Text("Text einfügen").tag(1); Text("App-Ordner").tag(2)
                }.pickerStyle(.segmented)
            }
            if source == 0 {
                Section("Dateien & iCloud Drive") {
                    Button { choose = true } label: { Label("Datei auswählen", systemImage: "folder") }.disabled(unavailable)
                    Text("Auch Dateien ohne erkannte JSON-Endung sind auswählbar. Der Inhalt wird nach dem Öffnen geprüft.").font(.caption).foregroundStyle(.secondary)
                }
            } else if source == 1 {
                Section("JSON-Inhalt") {
                    TextEditor(text: $text).font(.system(.caption, design: .monospaced)).frame(minHeight: 190)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().privacySensitive()
                        .accessibilityLabel("JSON-Inhalt einfügen")
                        .disabled(unavailable)
                    PasteButton(payloadType: String.self) { values in
                        if let value = values.first { text = value }
                    }.disabled(unavailable)
                    TextField("Dateiname, z. B. secrets.json", text: $localName).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("Inhalt prüfen & übernehmen") { acceptText(save: false) }.disabled(text.isEmpty || unavailable)
                    Button("Als JSON im App-Ordner speichern") { acceptText(save: true) }.disabled(text.isEmpty || unavailable)
                    Text("Speichern erstellt eine lokale JSON-Datei. Erst „Importieren“ sendet sie an deinen Server.").font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Section("Auf meinem iPhone → RJ Tracker → Imports") {
                    Text("In der Dateien-App Dateien in RJ Tracker oder dessen Ordner Imports kopieren. Am Computer ist der App-Ordner auch über die Dateifreigabe erreichbar.").font(.subheadline).foregroundStyle(.secondary)
                    Button("Ordner neu einlesen", systemImage: "arrow.clockwise") { refreshFiles() }.disabled(unavailable)
                    if localFiles.isEmpty {
                        Label("Noch keine JSON-Dateien im App-Ordner", systemImage: "tray").foregroundStyle(.secondary)
                    }
                    ForEach(localFiles) { local in
                        Button { Task { await read(local.url) } } label: {
                            HStack {
                                Image(systemName: "doc.text").foregroundStyle(.blue)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(local.url.lastPathComponent).foregroundStyle(.primary).lineLimit(2)
                                    Text("\(ByteCountFormatter.string(fromByteCount: Int64(local.size), countStyle: .file)) · \(local.modified.formatted(date: .abbreviated, time: .shortened))")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }.disabled(unavailable)
                    }
                    Text("Schlüsseldateien sind vertraulich. Du kannst die lokale Kopie nach dem Import in der Dateien-App löschen.").font(.caption).foregroundStyle(.secondary)
                }
            }
            if let file {
                Section("Bereit zum Import") {
                    Label(file.name, systemImage: "checkmark.seal.fill").foregroundStyle(.green).lineLimit(2)
                    Text("Gültiges JSON · \(ByteCountFormatter.string(fromByteCount: Int64(file.data.count), countStyle: .file))").font(.caption).foregroundStyle(.secondary)
                    if provider == "apple" {
                        TextField("Eindeutiger Trackername", text: $name).autocorrectionDisabled()
                        Toggle("Vorhandenen Tracker ausdrücklich ersetzen", isOn: $replace)
                    }
                    Button("Auf Server importieren", systemImage: "square.and.arrow.up") { confirm = true }
                        .disabled(unavailable || (provider == "apple" && name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
                }
            }
            if unavailable { ProgressView(reading ? "Datei wird geöffnet …" : "Import läuft …") }
            if !message.isEmpty {
                Section {
                    Label(message, systemImage: failed ? "exclamationmark.circle" : "info.circle")
                        .foregroundStyle(failed ? Color.orange : Color.secondary).textSelection(.enabled)
                }
            }
        }.rjListChrome().navigationTitle("JSON importieren").navigationBarTitleDisplayMode(.inline)
        .task { localName = provider == "google" ? "secrets.json" : "Tracker.json"; refreshFiles() }
        .onChange(of: source) { _, _ in refreshFiles() }
        .onChange(of: text) { _, _ in file = nil }
        .sheet(isPresented: $choose) {
            JSONDocumentPicker(onPick: { url in choose = false; Task { await read(url) } }, onCancel: { choose = false })
        }
        .confirmationDialog(replace ? "Vorhandene Tracker-Schlüssel ersetzen?" : "Datei auf deinen Server importieren?", isPresented: $confirm, titleVisibility: .visible) {
            Button("Importieren", role: replace ? .destructive : nil) { Task { await upload() } }
        }
    }
    private func refreshFiles() {
        do { localFiles = try ImportStorage.files() }
        catch { message = error.localizedDescription; failed = true }
    }
    private func accept(_ accepted: JSONImportFile) {
        file = accepted; failed = false; message = "JSON bereit. Zum Import bestätigen."
        if name.isEmpty { name = (accepted.name as NSString).deletingPathExtension }
    }
    private func acceptText(save: Bool) {
        file = nil
        do {
            let accepted = JSONImportFile(name: localName.isEmpty ? "Import.json" : localName, data: Data(text.utf8))
            _ = try accepted.object()
            if save {
                let url = try ImportStorage.save(accepted)
                accept(JSONImportFile(name: url.lastPathComponent, data: accepted.data))
                message = "\(url.lastPathComponent) in RJ Tracker/Imports gespeichert. Bereit zum Import."
                refreshFiles()
            } else { accept(accepted) }
        } catch { message = error.localizedDescription; failed = true }
    }
    @MainActor private func read(_ url: URL) async {
        reading = true; file = nil; failed = false; defer { reading = false }
        do { let accepted = try await Task.detached(priority: .userInitiated) { try ImportStorage.read(url) }.value; accept(accepted) }
        catch { message = error.localizedDescription; failed = true }
    }
    private func upload() async {
        guard let file else { return }; busy = true; defer { busy = false }
        do {
            let content = try file.object()
            let r = try await APIClient.shared.requestJSON(path: "/api/v3/import", method: "POST", json: ["provider": provider, "name": name, "content": content, "replace": replace])
            self.file = nil; text = ""; message = r["message"].stringValue ?? "Import abgeschlossen."; failed = false
            Haptics.success(); await model.refresh()
        } catch { message = error.localizedDescription; failed = true }
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
