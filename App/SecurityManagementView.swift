import SwiftUI
import CoreImage.CIFilterBuiltins
import SafariServices

struct SecurityManagementView: View {
    var body: some View {
        List {
            NavigationLink("Passwort ändern") {
                ManagementForm(title: "Passwort ändern", path: "/api/security/password", fields: [
                    .init(id: "current_password", label: "Aktuelles Passwort", kind: .secret, required: true),
                    .init(id: "new_password", label: "Neues Passwort · mindestens 10 Zeichen", kind: .secret, required: true, minimum: 10),
                    .init(id: "confirm_password", label: "Neues Passwort wiederholen", kind: .secret, required: true, minimum: 10)
                ], explanation: "Andere Sitzungen müssen sich anschließend neu anmelden. Die beiden neuen Passwörter müssen übereinstimmen.")
            }
            NavigationLink("Zwei-Faktor-Schutz") { TwoFactorManagementView() }
            NavigationLink("Passkeys verwalten") { PasskeyManagementView() }
        }.navigationTitle("Sicherheit").navigationBarTitleDisplayMode(.inline)
    }
}

struct TwoFactorManagementView: View {
    @State private var status: JSONValue = .null
    @State private var setup: JSONValue = .null
    @State private var recovery: [JSONValue] = []
    @State private var error: String?
    private var enabled: Bool { status["enabled"].boolValue == true }
    var body: some View {
        List {
            Section { Label(enabled ? "Zwei-Faktor-Schutz aktiv" : "Zwei-Faktor-Schutz nicht aktiv", systemImage: enabled ? "checkmark.shield.fill" : "shield"); if let error { Text(error).foregroundStyle(.red) } }
            if recovery.isEmpty {
                NavigationLink(enabled ? "Authenticator neu einrichten" : "Authenticator einrichten") {
                    ManagementForm(title: "Einrichtung starten", path: "/api/security/2fa/setup", fields: [
                        .init(id: "current_password", label: "Aktuelles Passwort", kind: .secret, required: true),
                        .init(id: "current_code", label: "Bisheriger 2FA-/Wiederherstellungscode", kind: .secret, required: enabled)
                    ], explanation: "Nach dem Start zurück zu dieser Seite: Dort erscheinen QR-Code und Bestätigung.") { setup = $0 }
                }
                if let token = setup["setup_token"].stringValue {
                    Section("Mit Authenticator scannen") {
                        if let uri = setup["otpauth_uri"].stringValue, let image = qr(uri) { Image(uiImage: image).interpolation(.none).resizable().scaledToFit().frame(maxWidth: 230).frame(maxWidth: .infinity).padding().background(.white) }
                        Text(setup["setup_key"].text).font(.system(.body, design: .monospaced)).textSelection(.enabled).privacySensitive()
                        Text("Alternativ den Schlüssel manuell im Authenticator hinzufügen. Er läuft nach zehn Minuten ab.").font(.caption).foregroundStyle(.secondary)
                        NavigationLink("Code bestätigen") {
                            ManagementForm(title: "2FA aktivieren", path: "/api/security/2fa/confirm", fields: [.init(id: "code", label: "Sechsstelliger Authenticator-Code", kind: .secret, required: true)], constants: ["setup_token": .string(token)], explanation: "Danach zurück zu dieser Seite, um die einmalig angezeigten Wiederherstellungscodes zu sichern.") {
                                recovery = $0["recovery_codes"].rows; status = $0["two_factor"]; setup = .null
                            }
                        }
                    }
                }
            } else {
                Section("Wiederherstellungscodes · jetzt sichern") {
                    Text("Diese Codes werden nur jetzt angezeigt. Bewahre sie an einem sicheren Ort auf.").foregroundStyle(.orange)
                    Text(recovery.map(\.text).joined(separator: "\n")).font(.system(.body, design: .monospaced)).textSelection(.enabled).privacySensitive()
                    Button("Codes gesichert") { recovery = [] }
                }
            }
            if enabled {
                NavigationLink("Zwei-Faktor-Schutz deaktivieren") {
                    ManagementForm(title: "2FA deaktivieren", path: "/api/security/2fa", method: "DELETE", fields: [
                        .init(id: "current_password", label: "Aktuelles Passwort", kind: .secret, required: true),
                        .init(id: "code", label: "2FA-/Wiederherstellungscode", kind: .secret, required: true)
                    ], confirmation: "Zwei-Faktor-Schutz wirklich deaktivieren?", destructive: true) { status = $0["two_factor"] }
                }
            }
        }.navigationTitle("Zwei-Faktor-Schutz").navigationBarTitleDisplayMode(.inline)
        .task { await load() }.refreshable { await load() }
    }
    private func load() async { do { status = try await APIClient.shared.requestJSON(path: "/api/security/2fa")["two_factor"]; error = nil } catch { self.error = error.localizedDescription } }
    private func qr(_ text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator(); filter.message = Data(text.utf8)
        guard let output = filter.outputImage, let cg = CIContext().createCGImage(output.transformed(by: CGAffineTransform(scaleX: 8, y: 8)), from: output.extent.applying(CGAffineTransform(scaleX: 8, y: 8))) else { return nil }
        return UIImage(cgImage: cg)
    }
}

struct PasskeyManagementView: View {
    @State private var credentials: [JSONValue] = []
    @State private var error: String?
    @State private var website = false
    var body: some View {
        List {
            Section {
                Text("Vorhandene Passkeys hier umbenennen oder entfernen. Neue Passkeys werden auf der HTTPS-Website deines Servers eingerichtet, an deren Domain sie gebunden sind.").font(.subheadline).foregroundStyle(.secondary)
                Button("Passkey auf der Website hinzufügen") { website = true }.disabled(APIClient.shared.baseURL?.scheme != "https")
                Text("Dort gegebenenfalls anmelden und Einstellungen → Sicherheit → Passkeys öffnen.").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(credentials, id: \.identifier) { key in
                Section(key["label"].text) {
                    LabeledContent("Synchronisierbar gesichert", value: key["backed_up"].text)
                    NavigationLink("Umbenennen") { ManagementForm(title: "Passkey umbenennen", path: "/api/security/passkeys/\(key.identifier)", method: "PATCH", fields: [.init(id: "label", label: "Name", required: true)], initial: ["label": key["label"]]) }
                    NavigationLink("Entfernen") {
                        ManagementForm(title: "Passkey entfernen", path: "/api/security/passkeys/\(key.identifier)", method: "DELETE", fields: [
                            .init(id: "current_password", label: "Aktuelles Passwort", kind: .secret, required: true),
                            .init(id: "current_code", label: "2FA-Code, falls aktiviert", kind: .secret)
                        ], constants: ["confirmed": .bool(true)], confirmation: "Diesen Passkey entfernen? Andere Sitzungen werden ungültig.", destructive: true)
                    }
                }
            }
            if credentials.isEmpty && error == nil { Text("Keine Passkeys registriert.").foregroundStyle(.secondary) }
            if let error { Text(error).foregroundStyle(.red) }
        }.navigationTitle("Passkeys").navigationBarTitleDisplayMode(.inline)
        .task { await load() }.refreshable { await load() }
        .sheet(isPresented: $website, onDismiss: { Task { await load() } }) {
            if let url = APIClient.shared.baseURL { ServerSafariView(url: url).ignoresSafeArea() }
        }
    }
    private func load() async { do { credentials = try await APIClient.shared.requestJSON(path: "/api/security/passkeys")["passkeys"]["credentials"].rows; error = nil } catch { self.error = error.localizedDescription } }
}
struct ServerSafariView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController { SFSafariViewController(url: url) }
    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) { }
}
