import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            switch model.connectionState {
            case .restoring:
                RJLaunchView().transition(.opacity)
            case .disconnected, .connecting, .needsTwoFactor:
                ConnectionView()
            case .connected:
                MainTabView().transition(.opacity)
            }
        }
        .tint(.blue)
        .animation(reduceMotion ? nil : .smooth(duration: 0.35), value: model.connectionState)
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
