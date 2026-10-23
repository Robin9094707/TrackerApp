import SwiftUI
import SpotIntegration

@main
struct RJTrackerApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage("appearance") private var appearance = "system"
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView().environment(model)
                .preferredColorScheme(appearance == "dark" ? .dark : appearance == "light" ? .light : nil)
                .task { try? ImportStorage.prepare(); await model.start(); await GoogleTrackerStore.shared.restoreIfNeeded() }
                .onChange(of: scenePhase) { _, phase in GoogleTrackerStore.shared.sceneChanged(active: phase == .active) }
        }
    }
}


