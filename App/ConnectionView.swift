import SwiftUI

struct ConnectionView: View {
    @Environment(AppModel.self) private var model
    @State private var password = ""
    @State private var code = ""
    @FocusState private var focused: Field?
    enum Field { case server, username, password, code }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    VStack(spacing: 10) {
                        Image(systemName: "point.3.connected.trianglepath.dotted").font(.system(size: 52, weight: .semibold)).symbolRenderingMode(.hierarchical)
                        Text("RJ Tracker").font(.largeTitle.bold())
                        Text("Deine Apple-, Google-, Samsung- und Fusion-Tracker nativ auf dem iPhone.").multilineTextAlignment(.center).foregroundStyle(.secondary)
                    }.padding(.top, 35)

                    VStack(spacing: 14) {
                        TextField("https://tracker.example.de", text: Binding(get: { model.serverURL }, set: { model.serverURL = $0 })).textContentType(.URL).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled().focused($focused, equals: .server)
                            .textFieldStyle(.roundedBorder)
                        TextField("Benutzername (optional)", text: Binding(get: { model.username }, set: { model.username = $0 })).textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled().focused($focused, equals: .username).textFieldStyle(.roundedBorder)
                        if model.connectionState != .needsTwoFactor {
                            SecureField("Passwort", text: $password).textContentType(.password).focused($focused, equals: .password).textFieldStyle(.roundedBorder)
                            Button { Task { await model.connect(password: password); if model.connectionState == .connected { password = "" } } } label: {
                                Label(model.connectionState == .connecting ? "Verbinde …" : "Mit Server koppeln", systemImage: "link.circle.fill").frame(maxWidth: .infinity)
                            }.buttonStyle(.borderedProminent).controlSize(.large).disabled(model.serverURL.isEmpty || password.isEmpty || model.connectionState == .connecting)
                        } else {
                            TextField("2FA-Code", text: $code).keyboardType(.numberPad).textContentType(.oneTimeCode).focused($focused, equals: .code).textFieldStyle(.roundedBorder)
                            Button { Task { await model.verify2FA(code: code) } } label: { Label("Code bestätigen", systemImage: "checkmark.shield.fill").frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent).controlSize(.large)
                        }
                    }.rjCard()

                    Label("Das Passwort wird nicht gespeichert. Für den laufenden Zugriff nutzt die App die sichere Server-Session und CSRF; HTTPS wird empfohlen.", systemImage: "lock.shield.fill")
                        .font(.footnote).foregroundStyle(.secondary).rjCard()
                }.padding()
            }.background(.background)
        }
    }
}
