import SwiftUI
import UserNotifications

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var signOutConfirm = false
    var body: some View {
        Form {
            Section("Verbindung") { LabeledContent("Server", value: model.serverURL); LabeledContent("Benutzer", value: model.bootstrap?.session?.user?.displayName ?? model.username); LabeledContent("Status", value: "Verbunden") }
            Section("Benachrichtigungen") {
                LabeledContent("APNs Backend", value: model.bootstrap?.push?.serverConfigured == true ? "Bereit" : "Nicht vollständig")
                Button("Berechtigung erneut anfordern") { Task { await PushManager.shared.requestAuthorization(); await PushManager.shared.registerIfPossible() } }
            }
            Section("Sicherheit") { Text("Das Server-Passwort wird nach dem Login verworfen. Der CSRF-Wert liegt im iOS-Keychain; die eigentliche Web-Session bleibt in der geschützten Cookie-Verwaltung von URLSession.").font(.footnote).foregroundStyle(.secondary) }
            Section { Button("Vom Server abmelden", role: .destructive) { signOutConfirm = true } }
        }.navigationTitle("Einstellungen").confirmationDialog("Wirklich abmelden?", isPresented: $signOutConfirm) { Button("Abmelden", role: .destructive) { Task { await model.signOut() } }; Button("Abbrechen", role: .cancel) {} }
    }
}
