import SwiftUI
import SpotIntegration

struct RootView: View {
    @ObservedObject private var google = GoogleTrackerStore.shared
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if model.showsMainInterface(localGoogleCredentials: google.hasCredentials) {
                MainTabView()
            } else if model.connectionState == .restoring { RJLaunchView().transition(.opacity) }
            else { ConnectionView() }
        }
        .sheet(isPresented: Binding(get: { model.showingServerConnection }, set: { model.showingServerConnection = $0 })) {
            ConnectionView(allowsClosing: true)
        }
        .onChange(of: model.connectionState) { _, state in
            if state == .connected { model.showingServerConnection = false }
        }
        .tint(.blue)
        .animation(reduceMotion ? nil : .smooth(duration: 0.35), value: model.connectionState)
        .alert("RJ Tracker", isPresented: Binding(get: { !model.showsMainInterface(localGoogleCredentials: google.hasCredentials) && model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
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
