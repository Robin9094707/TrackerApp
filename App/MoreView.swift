import SwiftUI

struct MoreView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    Image(systemName: "person.crop.circle.fill").font(.system(size: 44)).foregroundStyle(.white, RJBrand.indigo)
                        .padding(6).rjGlassSurface(Circle(), tint: RJBrand.indigo.opacity(0.25))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.bootstrap?.session?.user?.displayName ?? (model.username.isEmpty ? "Mein Tracker-Konto" : model.username)).font(.title3.bold())
                        Text("\(model.trackers.count) Objekte · \(model.trackers.filter { $0.favorite == true }.count) Favoriten").font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(.vertical, 8)
                SyncStatusView()
            }
            if !model.serverActionsAvailable {
                Section { Button("Mit Tracker-Server verbinden", systemImage: "network") { model.showingServerConnection = true } }
            }
            if model.serverActionsAvailable {
                Section("Konto") {
                    NavigationLink { AccountManagementView() } label: { Label("Konto & Sicherheit", systemImage: "person.badge.shield.checkmark").labelStyle(.rjIcon(.blue)) }
                    NavigationLink { InternalSharesView() } label: { Label("Interne Freigaben", systemImage: "person.2").labelStyle(.rjIcon(.green)) }
                }
            }
            if model.showsGoogleControls { Section("Google Find Hub") { GoogleLauncherCard() } }
            if model.serverActionsAvailable {
                if let webApp = webAppURL {
                    Section {
                        Link(destination: webApp) {
                            HStack(spacing: 12) {
                                Image(systemName: "globe").foregroundStyle(.white)
                                    .frame(width: 30, height: 30)
                                    .background(RJBrand.gradient, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Web-App öffnen").font(.body.weight(.semibold)).foregroundStyle(.primary)
                                    Text(webApp.absoluteString).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer()
                                Image(systemName: "arrow.up.right").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
                            }
                        }
                    } footer: {
                        Text("Alle Ortungsfunktionen, Verlauf und Taschen im Browser – mit demselben Login.")
                    }
                }
                Section("Meine Objekte") {
                    NavigationLink { SchoolBagHub() } label: { Label("Taschen & Wochenübersicht", systemImage: "backpack.fill").labelStyle(.rjIcon(.indigo)) }
                    NavigationLink { BarkSettingsView() } label: { Label("Bark & Sammelmeldungen", systemImage: "bell.badge.fill").labelStyle(.rjIcon(.red)) }
                    NavigationLink { GroupsView() } label: { Label("Gruppen", systemImage: "folder").labelStyle(.rjIcon(.orange)) }
                    NavigationLink { ArchiveView() } label: { Label("Archiv & ausgeblendete Objekte", systemImage: "archivebox").labelStyle(.rjIcon(.brown)) }
                }
                Section {
                    NavigationLink { SystemStatusView() } label: { Label("Serverzentrale", systemImage: "waveform.path.ecg").labelStyle(.rjIcon(.pink)) }
                    NavigationLink { ProviderSetupView() } label: { Label("Accounts, Import & Fusionen", systemImage: "plus.circle.fill").labelStyle(.rjIcon(.purple)) }
                    NavigationLink { ClientAccessView() } label: { Label("Geräte & API-Schlüssel", systemImage: "key.horizontal").labelStyle(.rjIcon(.gray)) }
                }
                Section("Server verwalten") {
                    NavigationLink { FindMyMaintenanceView() } label: { Label("FindMy.py & Serverpakete", systemImage: "shippingbox").labelStyle(.rjIcon(.teal)) }
                    NavigationLink { MCPManagementView() } label: { Label("ChatGPT / MCP", systemImage: "bubble.left.and.text.bubble.right").labelStyle(.rjIcon(.mint)) }
                    NavigationLink { BackupsManagementView() } label: { Label("Backups & Wiederherstellung", systemImage: "externaldrive.badge.timemachine").labelStyle(.rjIcon(.cyan)) }
                    NavigationLink { NetworkComparisonView() } label: { Label("Netzwerkvergleich", systemImage: "chart.bar.xaxis").labelStyle(.rjIcon(.blue)) }
                    if model.showsGoogleControls { NavigationLink { GoogleRepairView() } label: { Label("Google-Reparatur", systemImage: "wrench.and.screwdriver").labelStyle(.rjIcon(.green)) } }
                    NavigationLink { StorageCleanupView() } label: { Label("Speicher bereinigen", systemImage: "externaldrive.badge.minus").labelStyle(.rjIcon(.orange)) }
                    NavigationLink { GlobalPollingView() } label: { Label("Automatische Ortung", systemImage: "pause.circle").labelStyle(.rjIcon(.indigo)) }
                }
            }
            Section {
                NavigationLink { SettingsView() } label: { Label("Einstellungen", systemImage: "gearshape").labelStyle(.rjIcon(.gray)) }
            }
            Section("Erweitert") {
                if model.serverActionsAvailable { NavigationLink { AdvancedToolsView() } label: { Label("API-Werkzeuge", systemImage: "terminal").labelStyle(.rjIcon(.black)) } }
                NavigationLink { DebugConsoleView() } label: { Label("Diagnoseprotokoll", systemImage: "ladybug").labelStyle(.rjIcon(.red)) }
            }
            Section {
                Text("RJ Tracker \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.0")")
                    .font(.footnote).foregroundStyle(.secondary).frame(maxWidth: .infinity)
            }.listRowBackground(Color.clear)
        }
        .scrollContentBackground(.hidden).rjScreenChrome().navigationTitle("Ich").navigationBarTitleDisplayMode(.inline)
        .refreshable { await model.refresh() }
    }

    private var webAppURL: URL? {
        var base = model.serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else { return nil }
        if !base.lowercased().hasPrefix("http") { base = "https://" + base }
        while base.hasSuffix("/") { base.removeLast() }
        return URL(string: base + "/app")
    }
}


