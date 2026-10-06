import SwiftUI

struct MoreView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    Image(systemName: "person.crop.circle.fill").font(.system(size: 48)).foregroundStyle(.blue)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.bootstrap?.session?.user?.displayName ?? model.username).font(.title3.bold())
                        Text("\(model.trackers.count) Objekte · \(model.trackers.filter { $0.favorite == true }.count) Favoriten").font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(.vertical, 8)
                SyncStatusView()
            }
            Section("Konto") {
                NavigationLink { AccountManagementView() } label: { Label("Konto & Sicherheit", systemImage: "person.badge.shield.checkmark") }
                NavigationLink { InternalSharesView() } label: { Label("Interne Freigaben", systemImage: "person.2") }
            }
            Section("Meine Objekte") {
                NavigationLink { GroupsView() } label: { Label("Gruppen", systemImage: "folder") }
                NavigationLink { ArchiveView() } label: { Label("Archiv & ausgeblendete Objekte", systemImage: "archivebox") }
            }
            Section {
                NavigationLink { SettingsView() } label: { Label("Einstellungen", systemImage: "gearshape") }
                NavigationLink { SystemStatusView() } label: { Label("Serverzentrale", systemImage: "waveform.path.ecg") }
                NavigationLink { ProviderSetupView() } label: { Label("Accounts, Import & Fusionen", systemImage: "plus.circle.fill") }
                NavigationLink { ClientAccessView() } label: { Label("Geräte & API-Schlüssel", systemImage: "key.horizontal") }
            }
            Section("Server verwalten") {
                NavigationLink { BackupsManagementView() } label: { Label("Backups & Wiederherstellung", systemImage: "externaldrive.badge.timemachine") }
                NavigationLink { NetworkComparisonView() } label: { Label("Netzwerkvergleich", systemImage: "chart.bar.xaxis") }
                NavigationLink { GoogleRepairView() } label: { Label("Google-Reparatur", systemImage: "wrench.and.screwdriver") }
                NavigationLink { StorageCleanupView() } label: { Label("Speicher bereinigen", systemImage: "externaldrive.badge.minus") }
                NavigationLink { GlobalPollingView() } label: { Label("Automatische Ortung", systemImage: "pause.circle") }
            }
            Section("Erweitert") {
                NavigationLink { AdvancedToolsView() } label: { Label("API-Werkzeuge", systemImage: "terminal") }
                NavigationLink { DebugConsoleView() } label: { Label("Diagnoseprotokoll", systemImage: "ladybug") }
            }
            Section {
                Text("RJ Tracker \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.0")")
                    .font(.footnote).foregroundStyle(.secondary).frame(maxWidth: .infinity)
            }.listRowBackground(Color.clear)
        }
        .scrollContentBackground(.hidden).rjScreenChrome().navigationTitle("Ich").navigationBarTitleDisplayMode(.inline)
        .refreshable { await model.refresh() }
    }
}


