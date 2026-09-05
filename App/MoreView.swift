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
            Section {
                NavigationLink { SettingsView() } label: { Label("Einstellungen", systemImage: "gearshape") }
                NavigationLink { SystemStatusView() } label: { Label("Verbindung & Netzwerke", systemImage: "waveform.path.ecg") }
                NavigationLink { WebStudioView() } label: { Label("Web Studio", systemImage: "safari") }
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
        .navigationTitle("Ich").navigationBarTitleDisplayMode(.inline)
        .refreshable { await model.refresh() }
    }
}
