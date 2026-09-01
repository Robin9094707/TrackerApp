import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            switch model.connectionState {
            case .restoring:
                ZStack {
                    RJGlassBackdrop()
                    VStack(spacing: 14) {
                        ProgressView()
                            .controlSize(.large)
                        Text("Verbindung wird wiederhergestellt …")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                    .rjCard()
                    .padding(28)
                }
            case .disconnected, .connecting, .needsTwoFactor:
                ConnectionView()
            case .connected:
                MainTabView()
            }
        }
        .tint(.blue)
        .alert("RJ Tracker", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

struct MainTabView: View {
    @State private var selection = 0

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack { TrackerHomeView() }
                .tabItem { Label("Objekte", systemImage: "airtag.radiowaves.forward") }
                .tag(0)

            NavigationStack { TrackerMapView() }
                .tabItem { Label("Karte", systemImage: "map.fill") }
                .tag(1)

            NavigationStack { AlertsView() }
                .tabItem { Label("Meldungen", systemImage: "bell.badge.fill") }
                .tag(2)

            NavigationStack { MoreView() }
                .tabItem { Label("Ich", systemImage: "person.crop.circle.fill") }
                .tag(3)
        }
        .toolbarBackground(.ultraThinMaterial, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
    }
}
