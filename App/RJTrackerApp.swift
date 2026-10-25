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
                .task { await model.start() }
                .task { _ = await Task.detached(priority: .utility) { try? ImportStorage.prepare() }.value }
                .task { await GoogleTrackerStore.shared.restoreIfNeeded() }
                .onChange(of: scenePhase) { _, phase in
                    GoogleTrackerStore.shared.sceneChanged(active: phase == .active)
                    if phase == .background { GoogleBackgroundRefresh.scheduleIfNeeded() }
                }
        }
        .backgroundTask(.appRefresh(GoogleBackgroundRefresh.identifier)) { await GoogleBackgroundRefresh.run() }
    }
}


