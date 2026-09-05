import SwiftUI

@main
struct RJTrackerApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage("appearance") private var appearance = "system"
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView().environment(model)
                .preferredColorScheme(appearance == "dark" ? .dark : appearance == "light" ? .light : nil)
                .task { await model.start() }
        }
    }
}

