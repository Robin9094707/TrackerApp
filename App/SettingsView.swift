import SwiftUI
import UserNotifications

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("appearance") private var appearance = "system"
    @State private var signOutConfirm = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Darstellung").font(.headline)
                    Picker("Erscheinungsbild", selection: $appearance) {
                        Text("Automatisch").tag("system")
                        Text("Hell").tag("light")
                        Text("Dunkel").tag("dark")
                    }.pickerStyle(.segmented)
                    Text("Die App folgt außerdem deinen Einstellungen für größere Schrift und reduzierte Bewegung.").font(.footnote).foregroundStyle(.secondary)
                }.rjCard()
                connectionCard
                notificationCard
                securityCard
                signOutCard
            }
            .padding(16)
            .padding(.bottom, 28)
        }
        .rjScreenChrome()
        .navigationTitle("Einstellungen")
        .navigationBarTitleDisplayMode(.large)
        .confirmationDialog("Wirklich abmelden?", isPresented: $signOutConfirm) {
            Button("Abmelden", role: .destructive) { Task { await model.signOut() } }
            Button("Abbrechen", role: .cancel) {}
        }
    }

    private var connectionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                RJSectionTitle(title: "Verbindung", subtitle: "Aktive Server-Sitzung", symbol: "network")
                Spacer()
                RJStatusPill(text: "Verbunden", symbol: "checkmark.circle.fill", tint: .green)
            }
            Divider()
            LabeledContent("Server", value: model.serverURL)
            LabeledContent("Benutzer", value: model.bootstrap?.session?.user?.displayName ?? model.username)
            if let date = model.lastRefresh {
                LabeledContent("Letzte Synchronisierung") {
                    Text(date.rjTimelineText)
                }
            }
        }
        .rjCard()
    }

    private var notificationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            RJSectionTitle(title: "Benachrichtigungen", subtitle: "APNs und iOS-Berechtigungen", symbol: "bell.badge.fill")
            Divider()
            LabeledContent("APNs Backend", value: model.bootstrap?.push?.serverConfigured == true ? "Bereit" : "Nicht vollständig")
            Button {
                Task {
                    await PushManager.shared.requestAuthorization()
                    await PushManager.shared.registerIfPossible()
                }
            } label: {
                Label("Berechtigung erneut anfordern", systemImage: "bell.and.waves.left.and.right")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .rjGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .rjCard()
    }

    private var securityCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            RJSectionTitle(title: "Sicherheit", subtitle: "Lokaler Schutz der Zugangsdaten", symbol: "lock.shield.fill")
            Divider()
            Text("Das Server-Passwort wird nach dem Login verworfen. Der CSRF-Wert liegt im iOS-Keychain; die eigentliche Web-Session bleibt in der geschützten Cookie-Verwaltung von URLSession.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .rjCard()
    }

    private var signOutCard: some View {
        Button(role: .destructive) { signOutConfirm = true } label: {
            Label("Vom Server abmelden", systemImage: "rectangle.portrait.and.arrow.right")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .rjGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

