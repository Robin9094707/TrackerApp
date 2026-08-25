import SwiftUI

struct MoreView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        List {
            Section("Tracking") {
                NavigationLink { GeofencesView() } label: { Label("Geofences", systemImage: "mappin.and.ellipse") }
                NavigationLink { SavedPlacesView() } label: { Label("Gespeicherte Orte", systemImage: "star.circle") }
            }
            Section("Server") {
                NavigationLink { WebStudioView() } label: { Label("Web Studio · alle Funktionen", systemImage: "safari.fill") }
                NavigationLink { SystemStatusView() } label: { Label("Systemstatus", systemImage: "server.rack") }
                NavigationLink { AdvancedToolsView() } label: { Label("Alle API-Werkzeuge", systemImage: "terminal.fill") }
                NavigationLink { DebugConsoleView() } label: { Label("Debug-Protokoll", systemImage: "ladybug.fill") }
            }
            Section("App") {
                NavigationLink { SettingsView() } label: { Label("Einstellungen", systemImage: "gearshape.fill") }
            }
        }.navigationTitle("Mehr").refreshable { await model.refresh() }
    }
}
