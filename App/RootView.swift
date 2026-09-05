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
        .alert("RJ Tracker", isPresented: Binding(get: { model.connectionState != .connected && model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

struct MainTabView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        TrackerHomeView()
            .task(id: scenePhase) {
                if scenePhase == .active { await model.foregroundUpdates() }
            }
    }
}
