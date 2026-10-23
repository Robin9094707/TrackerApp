// RJ Tracker: local GoogleFindMyTools/Spot secrets import. GPL-3.0-only.
import SwiftUI
import UniformTypeIdentifiers
import LUI

struct LocalGoogleImportView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var chooseFile = false
    @State private var busy = false
    @State private var message: String?
    @State private var confirm = false
    var body: some View {
        Form {
            Section {
                Label("Google-Zugang auf diesem iPhone", systemImage: "lock.iphone").font(.headline)
                Text("Importiere eine secrets.json mit username, aas_token und optional owner_key/shared_key. Die Schlüssel werden im Schlüsselbund gespeichert. Die Google-Push-Registrierung wird für dieses iPhone eingerichtet.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Button("JSON-Datei auswählen", systemImage: "doc.badge.plus") { chooseFile = true }
                TextEditor(text: $text).frame(minHeight: 160).font(.system(.caption, design: .monospaced))
                    .autocorrectionDisabled().textInputAutocapitalization(.never).privacySensitive()
                Button("Lokal importieren") { confirm = true }.disabled(text.isEmpty || busy)
                if busy { ProgressView("Google-Zugang prüfen …") }
                if let message { Text(message).font(.footnote).foregroundStyle(.orange) }
            } footer: {
                Text("Der Import ersetzt ausschließlich den lokalen Google-Zugang. Deine Serverzugänge und Serverdaten bleiben erhalten. Fehlen Entschlüsselungsschlüssel, kannst du sie nach der Anmeldung bei Google wiederherstellen.")
            }
        }
        .disabled(busy)
        .navigationTitle("Google JSON importieren").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Schließen") { dismiss() }.disabled(busy) } }
        .fileImporter(isPresented: $chooseFile, allowedContentTypes: [.json, .data]) { result in
            do {
                let url = try result.get()
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let data = try Data(contentsOf: url, options: .mappedIfSafe)
                guard data.count <= 2_000_000, let value = String(data: data, encoding: .utf8) else {
                    throw importError("Bitte eine UTF-8-JSON-Datei unter 2 MB auswählen.")
                }
                text = value
            } catch { message = error.localizedDescription }
        }
        .confirmationDialog("Lokalen Google-Zugang importieren?", isPresented: $confirm, titleVisibility: .visible) {
            Button("Zugang prüfen und lokal speichern") { Task { await importSecrets() } }
        }
    }
    private func importError(_ text: String) -> NSError {
        NSError(domain: "SpotImport", code: 1, userInfo: [NSLocalizedDescriptionKey: text])
    }
    @MainActor private func importSecrets() async {
        busy = true; message = nil
        defer { busy = false }
        do {
            guard let data = text.data(using: .utf8), data.count <= 2_000_000,
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let username = json["username"] as? String, username.contains("@"),
                  let token = json["aas_token"] as? String, !token.isEmpty else {
                throw importError("Gültige secrets.json mit username und aas_token erforderlich.")
            }
            func hexKey(_ name: String) throws -> String? {
                guard let value = json[name] as? String, !value.isEmpty else { return nil }
                guard value.count == 64, value.allSatisfy({ $0.isHexDigit }) else {
                    throw importError("\(name) muss ein Schlüssel mit 64 Hex-Zeichen sein.")
                }
                return value
            }
            let owner = try hexKey("owner_key")
            let shared = try hexKey("shared_key")
            let version = json["owner_key_version"] as? Int ?? 1
            guard version > 0 else { throw importError("Ungültige owner_key_version.") }
            try await prepareGoogleConnection()
            guard let androidID = PushReceiver.sharedInstance.getAndroidId() else {
                throw importError("Google-Registrierung fehlt.")
            }
            let result: [String: String] = try await withCheckedThrowingContinuation { continuation in
                PlayServicesOAuth.performOauth(email: username, aasToken: token, androidID: String(androidID),
                    service: "oauth2:https://www.googleapis.com/auth/android_device_manager", app: "com.google.android.apps.adm") {
                    continuation.resume(with: $0)
                }
            }
            guard let auth = result["Auth"], !auth.isEmpty else {
                throw importError("Google hat den importierten Zugang nicht bestätigt. Der bisherige Zugang wurde beibehalten.")
            }
            // Validate storage before changing the in-memory session. Roll back a partial write.
            let previous = TokenManager.sharedInstance
            let oldToken = previous.aasToken, oldOwner = previous.ownerKey, oldShared = previous.sharedKey
            do {
                try KeychainStore.shared.save(token, for: .aasToken)
                try KeychainStore.shared.save(owner, for: .ownerKey)
                try KeychainStore.shared.save(shared, for: .sharedKey)
            } catch {
                try? KeychainStore.shared.save(oldToken, for: .aasToken)
                try? KeychainStore.shared.save(oldOwner, for: .ownerKey)
                try? KeychainStore.shared.save(oldShared, for: .sharedKey)
                throw error
            }
            BluetoothManager.sharedInstance.reset()
            previous.clearCachedTokens()
            Settings.sharedInstance.devicesList = nil
            previous.username = username
            previous.aasToken = token
            previous.ownerKey = owner
            previous.sharedKey = shared
            previous.ownerKeyVersion = version
            LUISettings.sharedInstance.appLaunchedBefore = true
            text = ""
            await GoogleTrackerStore.shared.refresh()
            if owner == nil { Settings.sharedInstance.showKeyRecoverySheet = true }
            dismiss()
        } catch { message = error.localizedDescription }
    }
}
