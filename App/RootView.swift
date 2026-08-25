import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            switch model.connectionState {
            case .restoring:
                ProgressView("Verbindung wird wiederhergestellt …")
            case .disconnected, .connecting, .needsTwoFactor:
                ConnectionView()
            case .connected:
                MainTabView()
            }
        }
        .alert("RJ Tracker", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            NavigationStack { TrackerHomeView() }
                .tabItem { Label("Objekte", systemImage: "smallcircle.filled.circle") }

            NavigationStack { TrackerMapView() }
                .tabItem { Label("Karte", systemImage: "map.fill") }

            NavigationStack { AlertsView() }
                .tabItem { Label("Meldungen", systemImage: "bell.badge.fill") }

            NavigationStack { MoreView() }
                .tabItem { Label("Mehr", systemImage: "person.crop.circle") }
        }
        .toolbarBackground(.ultraThinMaterial, for: .tabBar)
    }
}
