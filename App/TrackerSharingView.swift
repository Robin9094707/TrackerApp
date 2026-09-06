import SwiftUI

struct TrackerSharingView: View {
    @Environment(\.dismiss) private var dismiss
    let tracker: Tracker
    @State private var options = NativeShareOptions()
    @State private var confirmCreate = false
    @State private var confirmRevoke = false
    @State private var busy = false
    @State private var error: String?
    @State private var sharedURL: URL?
    @State private var expiresAt: Int?
    var body: some View {
        Form {
            if let sharedURL {
                Section {
                    Label("Freigabe bereit", systemImage: "checkmark.shield.fill").foregroundStyle(.green)
                    Text(sharedURL.absoluteString).font(.footnote).textSelection(.enabled)
                    ShareLink(item: sharedURL) { Label("Link teilen", systemImage: "square.and.arrow.up") }
                    if let expiresAt, expiresAt > 0 {
                        LabeledContent("Gültig bis", value: Date(timeIntervalSince1970: TimeInterval(expiresAt)).formatted(date: .abbreviated, time: .shortened))
                    }
                    Text("Das Passwort wird nicht mit dem Link geteilt. Gib es deinem Gast separat.").font(.footnote).foregroundStyle(.secondary)
                }
            } else {
                Section {
                    Label(tracker.name, systemImage: "person.2")
                    Text("Der Gast kann dieses Objekt und vorhandene verknüpfte Ortungsnetze sehen. Ein neu erstellter Link ersetzt bestehende Gastlinks für dieses Objekt.").font(.footnote).foregroundStyle(.secondary)
                }
                Section("Zugang") {
                    SecureField("Gast-Passwort (mindestens 4 Zeichen)", text: $options.password).textContentType(.newPassword)
                    Picker("Gültigkeit", selection: $options.expiryHours) {
                        Text("1 Stunde").tag(1); Text("6 Stunden").tag(6); Text("24 Stunden").tag(24)
                        Text("3 Tage").tag(72); Text("7 Tage").tag(168); Text("30 Tage").tag(720)
                    }
                }
                Section("Was darf der Gast?") {
                    Toggle("Neue Ortung anfordern", isOn: $options.canLocate)
                    Toggle("Standortverlauf ansehen", isOn: $options.showHistory)
                    Picker("Standort teilen", selection: $options.precision) {
                        Text("Genau").tag("exact"); Text("Ungefähr 100 m").tag("100m")
                        Text("Ungefähr 500 m").tag("500m"); Text("Stadtbereich").tag("city")
                    }
                }
                Section { Button("Freigabe erstellen") { confirmCreate = true }.disabled(options.password.count < 4 || busy) }
            }
            Section { Button("Gastfreigabe widerrufen", role: .destructive) { confirmRevoke = true }.disabled(busy) }
            if let error { Section { Text(error).foregroundStyle(.red) } }
        }
        .navigationTitle("Objekt freigeben").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() }.disabled(busy) } }
        .disabled(busy)
        .interactiveDismissDisabled(busy)
        .confirmationDialog("Neue Freigabe erstellen?", isPresented: $confirmCreate, titleVisibility: .visible) {
            Button("Erstellen und bisherige Links ersetzen") { Task { await create() } }
        } message: { Text("Bestehende Gastlinks für dieses Objekt werden dabei ungültig.") }
        .confirmationDialog("Alle Gastlinks für dieses Objekt widerrufen?", isPresented: $confirmRevoke, titleVisibility: .visible) {
            Button("Widerrufen", role: .destructive) { Task { await revoke() } }
        }
    }
    private func create() async {
        guard !busy else { return }; busy = true; error = nil; defer { busy = false }
        do {
            let result = try await APIClient.shared.requestForm(path: "/api/share/\(tracker.apiID)", values: options.form)
            guard let id = result["link_id"].stringValue, let base = APIClient.shared.baseURL else { throw APIError.message("Der Server hat keinen Freigabelink zurückgegeben.") }
            sharedURL = base.appendingPathComponent("shared").appendingPathComponent(id)
            expiresAt = result["expires_ts"].integer
            options.password = ""
        } catch { self.error = error.localizedDescription }
    }
    private func revoke() async {
        busy = true; error = nil; defer { busy = false }
        do { _ = try await APIClient.shared.requestJSON(path: "/api/share/\(tracker.apiID)", method: "DELETE"); sharedURL = nil }
        catch { self.error = error.localizedDescription }
    }
}
