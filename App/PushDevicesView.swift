import SwiftUI
import CryptoKit

struct PushDevicesResponse: Decodable {
    var devices: [PushDevice]
    var push: PushStatus?
}

struct PushDevice: Decodable, Identifiable {
    let id: String
    var label: String?
    var enabled: Bool?
    var appVersion: String?
    var deviceModel: String?
    var updatedTS: Int?
    var lastSuccessTS: Int?
    var lastError: String?
    enum CodingKeys: String, CodingKey {
        case id, label, enabled
        case appVersion = "app_version"
        case deviceModel = "device_model"
        case updatedTS = "updated_ts"
        case lastSuccessTS = "last_success_ts"
        case lastError = "last_error"
    }
}

struct PushDevicesView: View {
    @State private var response: PushDevicesResponse?
    @State private var loading = false
    @State private var error: String?
    @State private var removal: PushDevice?
    @State private var removing = false
    private var currentID: String? {
        guard let token = PushManager.shared.token else { return nil }
        return String(SHA256.hash(data: Data(token.lowercased().utf8)).map { String(format: "%02x", $0) }.joined().prefix(20))
    }
    var body: some View {
        List {
            Section {
                Label("Deine Benachrichtigungen", systemImage: "iphone.radiowaves.left.and.right").font(.headline)
                Text("Hier siehst du, auf welchen Geräten der Server Push-Mitteilungen zustellt.").font(.subheadline).foregroundStyle(.secondary)
            }
            if loading { ProgressView("Geräte werden geladen …") }
            if let error {
                Section {
                    Text(error).font(.footnote).foregroundStyle(.orange)
                    Button("Erneut versuchen") { Task { await load() } }
                }
            }
            if let devices = response?.devices {
                if devices.isEmpty { ContentUnavailableView("Keine Push-Geräte", systemImage: "bell.slash", description: Text("Aktiviere Mitteilungen in den Einstellungen, um dein iPhone zu registrieren.")) }
                ForEach(devices) { device in
                    Section {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "iphone").font(.title2).foregroundStyle(.blue).frame(width: 36)
                            VStack(alignment: .leading, spacing: 7) {
                                HStack {
                                    Text(device.label ?? "iPhone").font(.headline)
                                    if device.id == currentID { Text("Dieses Gerät").font(.caption).foregroundStyle(.secondary) }
                                }
                                Text([device.deviceModel, device.appVersion.map { "App " + $0 }].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(.secondary)
                                RJStatusPill(text: device.enabled == false ? "Deaktiviert" : "Registriert", symbol: device.enabled == false ? "bell.slash" : "bell.badge", tint: device.enabled == false ? .secondary : .blue)
                                if let time = device.lastSuccessTS, time > 0 {
                                    Text("Zuletzt zugestellt: \(Date(timeIntervalSince1970: TimeInterval(time)).rjTimelineText)").font(.caption).foregroundStyle(.secondary)
                                }
                                if let message = device.lastError, !message.isEmpty {
                                    Text(message).font(.caption).foregroundStyle(.orange)
                                }
                            }
                        }.padding(.vertical, 6)
                        if device.id != currentID {
                            Button("Registrierung entfernen", role: .destructive) { removal = device }.disabled(removing)
                        }
                    }
                }
            }
        }
        .rjListChrome().navigationTitle("Push-Geräte").navigationBarTitleDisplayMode(.inline)
        .task { await load() }.refreshable { await load() }
        .confirmationDialog("Push-Gerät entfernen?", isPresented: Binding(get: { removal != nil }, set: { if !$0 { removal = nil } }), titleVisibility: .visible) {
            if let removal {
                Button("Registrierung entfernen", role: .destructive) { Task { await remove(removal) } }
            }
        } message: { Text("Dieses Gerät erhält danach keine Push-Mitteilungen mehr. Es kann sich beim nächsten Anmelden erneut registrieren.") }
    }
    @MainActor private func load() async {
        guard !loading else { return }; loading = true; error = nil; defer { loading = false }
        do { response = try await APIClient.shared.pushDevices() }
        catch is CancellationError { } catch { self.error = error.localizedDescription }
    }
    @MainActor private func remove(_ device: PushDevice) async {
        guard !removing else { return }; removing = true; defer { removing = false; removal = nil }
        do {
            try await APIClient.shared.removePushDevice(id: device.id)
            response?.devices.removeAll { $0.id == device.id }; Haptics.success()
        } catch { self.error = error.localizedDescription }
    }
}
