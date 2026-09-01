import SwiftUI

struct ConnectionView: View {
    @Environment(AppModel.self) private var model
    @State private var password = ""
    @State private var code = ""
    @FocusState private var focused: Field?

    enum Field { case server, username, password, code }

    var body: some View {
        NavigationStack {
            ZStack {
                RJGlassBackdrop()

                ScrollView {
                    VStack(spacing: 22) {
                        hero
                        connectionCard
                        privacyCard
                    }
                    .padding(18)
                    .padding(.top, 24)
                    .padding(.bottom, 36)
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
    }

    private var hero: some View {
        VStack(spacing: 11) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 86, height: 86)
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 43, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.tint)
            }
            .rjGlass(in: Circle())

            Text("RJ Tracker")
                .font(.largeTitle.bold())
            Text("Apple-, Google-, Samsung- und Fusion-Tracker in einer nativen iPhone-App.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
    }

    private var connectionCard: some View {
        VStack(spacing: 14) {
            HStack {
                RJSectionTitle(
                    title: model.connectionState == .needsTwoFactor ? "Zwei-Faktor-Anmeldung" : "Mit Server verbinden",
                    subtitle: "Sichere Session mit deinem Tracker-Backend",
                    symbol: "link.circle.fill"
                )
                Spacer()
            }

            Divider()

            if model.connectionState != .needsTwoFactor {
                inputField(symbol: "network", title: "Server") {
                    TextField("https://tracker.example.de", text: Binding(get: { model.serverURL }, set: { model.serverURL = $0 }))
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focused, equals: .server)
                }

                inputField(symbol: "person.fill", title: "Benutzer") {
                    TextField("Benutzername (optional)", text: Binding(get: { model.username }, set: { model.username = $0 }))
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focused, equals: .username)
                }

                inputField(symbol: "lock.fill", title: "Passwort") {
                    SecureField("Passwort", text: $password)
                        .textContentType(.password)
                        .focused($focused, equals: .password)
                }

                Button {
                    Task {
                        await model.connect(password: password)
                        if model.connectionState == .connected { password = "" }
                    }
                } label: {
                    HStack(spacing: 9) {
                        if model.connectionState == .connecting { ProgressView().controlSize(.small) }
                        else { Image(systemName: "link.circle.fill") }
                        Text(model.connectionState == .connecting ? "Verbinde …" : "Mit Server koppeln")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .rjGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(model.serverURL.isEmpty || password.isEmpty || model.connectionState == .connecting)
            } else {
                inputField(symbol: "checkmark.shield.fill", title: "2FA-Code") {
                    TextField("2FA-Code", text: $code)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .focused($focused, equals: .code)
                }

                Button { Task { await model.verify2FA(code: code) } } label: {
                    Label("Code bestätigen", systemImage: "checkmark.shield.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .rjGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(code.isEmpty)
            }
        }
        .rjCard()
    }

    private var privacyCard: some View {
        Label(
            "Das Passwort wird nicht gespeichert. Für den laufenden Zugriff nutzt die App die sichere Server-Session und CSRF; HTTPS wird empfohlen.",
            systemImage: "lock.shield.fill"
        )
        .font(.footnote)
        .foregroundStyle(.secondary)
        .rjCard()
    }

    private func inputField<Content: View>(
        symbol: String,
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 11) {
            Image(systemName: symbol)
                .foregroundStyle(.tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                content()
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .rjGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
