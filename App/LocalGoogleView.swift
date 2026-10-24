import SwiftUI
import SpotIntegration
import UniformTypeIdentifiers
import WebKit
import MapKit

struct LocalGoogleDestination: Identifiable { let id = UUID(); var deviceID: String? = nil }
struct LocalGoogleView: View {
    var deviceID: String? = nil
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Group {
                if let deviceID { NativeGoogleTrackerView(deviceID: deviceID) }
                else { GoogleAccountView() }
            }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Schließen") { dismiss() }.accessibilityLabel("Zurück zu RJ Tracker") } }
        }
    }
}
struct GoogleLauncherCard: View {
    var deviceID: String? = nil
    @ObservedObject private var google = GoogleTrackerStore.shared
    @State private var open = false
    var body: some View {
        Button { open = true } label: {
            HStack(spacing: 14) {
                Image(systemName: "sensor.tag.radiowaves.forward.fill").font(.title2).foregroundStyle(.green)
                    .frame(width: 48, height: 48).background(.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Google Find Hub").font(.headline).foregroundStyle(.primary)
                    Text(google.hasCredentials ? "\(google.trackers.count) Objekte · direkt verbunden" : "Google-Konto verbinden")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(); Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.secondary)
            }.contentShape(Rectangle()).padding(.vertical, 4)
        }.buttonStyle(.plain).accessibilityIdentifier("local-google-launcher")
        .sheet(isPresented: $open) { LocalGoogleView(deviceID: deviceID) }
    }
}

struct GoogleAccountView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var google = GoogleTrackerStore.shared
    @State private var busy = false
    @State private var message: String?
    @State private var auth: GoogleAuthDestination?
    @State private var importing = false
    @State private var json = ""
    @State private var chooseFile = false
    @State private var confirmSignOut = false
    @State private var invitation = ""
    var body: some View {
        Form {
            Section {
                Label(google.account ?? "Deine Google-Tracker", systemImage: "person.crop.circle.fill").font(.headline)
                Text(google.hasCredentials ? "Der gespeicherte Google-Zugang wird weiterverwendet. Deine Tracker gehören direkt zur Objektübersicht." : "Melde dich bei Google an. Tokens und Schlüssel bleiben im Schlüsselbund dieses iPhones.")
                    .font(.subheadline).foregroundStyle(.secondary)
                if google.hasCredentials {
                    if model.connectionState != .connected {
                        Button("Google in der Objektübersicht nutzen", systemImage: "map") { model.localMode = true; dismiss() }
                    }
                    Button("Google-Anmeldung erneuern", systemImage: "person.badge.key.fill") { run { auth = GoogleAuthDestination(url: try await google.prepareLogin(), recovery: false) } }
                    Button("Tracker und Reports aktualisieren", systemImage: "arrow.clockwise") { run { await google.refresh() } }
                    Button("Google-Schlüssel entsperren", systemImage: "key.fill") { run { auth = GoogleAuthDestination(url: try await google.recoveryURL(), recovery: true) } }
                    if google.needsKeys { Label("Schlüssel noch gesperrt – Anmeldung bleibt erhalten", systemImage: "lock.fill").foregroundStyle(.orange) }
                } else {
                    Button("Bei Google anmelden", systemImage: "person.badge.key.fill") { run { auth = GoogleAuthDestination(url: try await google.prepareLogin(), recovery: false) } }
                    Button("Vorherige Anmeldung fortsetzen") { run { await google.restoreIfNeeded(); if !google.hasCredentials { auth = GoogleAuthDestination(url: try await google.prepareLogin(), recovery: false) } } }
                }
                if busy || google.isRefreshing { ProgressView(google.statusMessage ?? "Google wird verbunden …") }
                if let error = message ?? google.errorMessage {
                    Text(error).font(.footnote).foregroundStyle(.orange).textSelection(.enabled)
                    Button("Erneut versuchen") { run { if google.hasCredentials { await google.refresh() } else { auth = GoogleAuthDestination(url: try await google.prepareLogin(), recovery: false) } } }
                }
            }
            if google.hasCredentials {
                Section("Aktualisierung") {
                    Picker("Im Vordergrund abrufen", selection: $google.refreshInterval) {
                        Text("Manuell").tag(0); Text("Jede Minute").tag(60); Text("Alle 2 Minuten").tag(120)
                        Text("Alle 5 Minuten").tag(300); Text("Alle 15 Minuten").tag(900)
                    }
                    Picker("Google-Meldungen", selection: $google.contributorMode) {
                        Text("Alle verfügbaren Bereiche").tag("AtAllAreas")
                        Text("Adaptiv").tag("Adaptive"); Text("Stark frequentierte Bereiche").tag("HighTrafficOnly")
                    }
                    Text("Jeder Abruf sammelt alle passenden Meldungen im Empfangsfenster. Google bestimmt, wann neue Standorte vorliegen. iOS begrenzt Hintergrundaktivität.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Bluetooth-Nahsuche aktivieren", systemImage: "dot.radiowaves.left.and.right") { google.requestBluetooth() }
                }
                Section("Google-Geräte") {
                    ForEach(google.trackers) { tracker in
                        NavigationLink { NativeGoogleTrackerView(deviceID: tracker.id) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(tracker.name)
                                Text("\(tracker.reportCount) Meldungen" + (tracker.nearby ? " · in der Nähe" : "")).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    if google.trackers.isEmpty { Text("Noch keine Geräte geladen. Aktualisieren oder später erneut versuchen.").foregroundStyle(.secondary) }
                }
                Section("Freigaben & eigene Tracker") {
                    TextField("Google-Freigabelink", text: $invitation).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("Einladung annehmen") { run { message = "Bestätigungs-PIN: " + (try await google.acceptInvitation(invitation)); invitation = "" } }.disabled(invitation.isEmpty)
                    Button("ESP32-Tracker erstellen") { run { message = "ESP32-Kennung: " + (try await google.createESP32()) } }
                }
            }
            Section("Zugang importieren") {
                Button("secrets.json lokal importieren", systemImage: "doc.badge.plus") { importing = true }
                Text("Der Import ist optional. Bestehende Serverzugänge und deren Daten bleiben unabhängig davon erhalten.").font(.caption).foregroundStyle(.secondary)
            }
            if google.hasCredentials {
                Section { Button("Google auf diesem iPhone abmelden", role: .destructive) { confirmSignOut = true } }
            }
        }
        .rjListChrome().navigationTitle("Google Find Hub").navigationBarTitleDisplayMode(.inline)
        .disabled(busy)
        .sheet(item: $auth) { destination in GoogleAuthenticationView(destination: destination) }
        .confirmationDialog("Lokalen Google-Zugang abmelden?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Abmelden", role: .destructive) { google.signOut() }
        } message: { Text("Deine gespeicherten Verläufe und die Serververbindung bleiben erhalten.") }
        .sheet(isPresented: $importing) {
            NavigationStack {
                Form {
                    Button("JSON-Datei öffnen") { chooseFile = true }
                    TextEditor(text: $json).font(.system(.caption, design: .monospaced)).frame(minHeight: 180).privacySensitive()
                    Button("Zugang prüfen und importieren") {
                        run { try await google.importSecrets(Data(json.utf8)); json = ""; importing = false }
                    }.disabled(json.isEmpty || busy)
                    if let message { Text(message).foregroundStyle(.orange) }
                }.navigationTitle("Google importieren")
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Schließen") { importing = false } } }
                    .fileImporter(isPresented: $chooseFile, allowedContentTypes: [.json, .data]) { result in
                        do {
                            let url = try result.get(); let access = url.startAccessingSecurityScopedResource()
                            defer { if access { url.stopAccessingSecurityScopedResource() } }
                            let data = try Data(contentsOf: url)
                            guard data.count <= 2_000_000, let text = String(data: data, encoding: .utf8) else { throw APIError.message("Bitte eine UTF-8-JSON-Datei unter 2 MB wählen.") }
                            json = text
                        } catch { message = error.localizedDescription }
                    }
            }
        }
        .task { await google.restoreIfNeeded() }
    }
    private func run(_ action: @escaping @MainActor () async throws -> Void) {
        busy = true; message = nil; google.clearError()
        Task { @MainActor in
            defer { busy = false }
            do { try await action() } catch { message = error is CancellationError ? nil : error.localizedDescription }
        }
    }
}

struct GoogleAuthDestination: Identifiable { let id = UUID(); let url: URL; let recovery: Bool }
struct GoogleAuthenticationView: View {
    let destination: GoogleAuthDestination
    @Environment(\.dismiss) private var dismiss
    @State private var message: String?
    @State private var busy = false
    @State private var webID = UUID()
    var body: some View {
        NavigationStack {
            GoogleAccountWebView(url: destination.url, recovery: destination.recovery) { value in
                guard !busy else { return }
                busy = true; message = nil
                Task { @MainActor in
                    defer { busy = false }
                    do {
                        if destination.recovery { try await GoogleTrackerStore.shared.recoverKeys(vaultKeys: value) }
                        else { try await GoogleTrackerStore.shared.finishLogin(oauthToken: value) }
                        dismiss()
                    } catch { message = error.localizedDescription }
                }
            }
            .id(webID)
            .safeAreaInset(edge: .top) {
                if busy { ProgressView(destination.recovery ? "Google-Schlüssel werden geprüft …" : "Anmeldung wird gespeichert …").padding(10) }
                if let message {
                    VStack { Text(message).font(.footnote).foregroundStyle(.orange)
                        Button("Noch einmal versuchen") { self.message = nil; webID = UUID() }
                    }.padding(12)
                }
            }
            .navigationTitle(destination.recovery ? "Schlüssel entsperren" : "Google anmelden").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Schließen") { dismiss() } } }
        }
    }
}
struct GoogleAccountWebView: UIViewRepresentable {
    let url: URL
    let recovery: Bool
    let onResult: (String) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "googleVault")
        if recovery {
            config.userContentController.addUserScript(WKUserScript(source: "window.mm={setVaultSharedKeys:function(s,k){window.webkit.messageHandlers.googleVault.postMessage(k);}};", injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = context.coordinator
        context.coordinator.start(view)
        view.load(URLRequest(url: url))
        return view
    }
    func updateUIView(_ view: WKWebView, context: Context) { context.coordinator.parent = self }
    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {
        coordinator.timer?.invalidate(); view.stopLoading(); view.configuration.userContentController.removeScriptMessageHandler(forName: "googleVault")
    }
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: GoogleAccountWebView
        var timer: Timer?
        var lastValue: String?
        init(_ parent: GoogleAccountWebView) { self.parent = parent }
        func start(_ view: WKWebView) {
            guard !parent.recovery else { return }
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self, weak view] _ in
                guard let self, view != nil else { return }
                WKWebsiteDataStore.default().httpCookieStore.getAllCookies { [weak self] cookies in
                    guard let self, let cookie = cookies.first(where: { GoogleTrackerStore.isOAuthCookie($0) }), self.lastValue != cookie.value else { return }
                    self.lastValue = cookie.value
                    self.parent.onResult(cookie.value)
                }
            }
        }
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            let origin = message.frameInfo.securityOrigin
            guard parent.recovery, message.frameInfo.isMainFrame, origin.protocol == "https", origin.host == "accounts.google.com" else { return }
            if let value = message.body as? String { parent.onResult(value) }
            else if JSONSerialization.isValidJSONObject(message.body), let data = try? JSONSerialization.data(withJSONObject: message.body), let value = String(data: data, encoding: .utf8) { parent.onResult(value) }
        }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if parent.recovery, navigationAction.request.url?.host == "myaccount.google.com" {
                webView.load(URLRequest(url: parent.url)); decisionHandler(.cancel)
            } else { decisionHandler(.allow) }
        }
    }
}
