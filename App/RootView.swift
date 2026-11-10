import SwiftUI
import SpotIntegration

struct RootView: View {
    @ObservedObject private var google = GoogleTrackerStore.shared
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var trackerLink: TrackerPushLink?

    var body: some View {
        Group {
            if model.showsMainInterface(localGoogleCredentials: google.hasCredentials) {
                MainTabView(trackerLink: $trackerLink)
            } else if model.connectionState == .restoring { RJLaunchView().transition(.opacity) }
            else { ConnectionView() }
        }
        .overlay { RJLaunchOverlay() }
        .onOpenURL { url in
            if let link = TrackerPushLink(url: url) { trackerLink = link }
        }
        .sheet(isPresented: Binding(get: { model.showingServerConnection }, set: { model.showingServerConnection = $0 })) {
            ConnectionView(allowsClosing: true)
        }
        .onChange(of: model.connectionState) { _, state in
            if state == .connected { model.showingServerConnection = false }
        }
        .tint(Color.accentColor)
        .animation(reduceMotion ? nil : .smooth(duration: 0.35), value: model.connectionState)
        .alert("RJ Tracker", isPresented: Binding(get: { !model.showsMainInterface(localGoogleCredentials: google.hasCredentials) && model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

struct MainTabView: View {
    @Binding var trackerLink: TrackerPushLink?
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        TrackerDashboardShell(trackerLink: $trackerLink)
            .task(id: scenePhase) {
                if scenePhase == .active { await model.foregroundUpdates() }
            }
    }
}

struct TrackerPushLink: Equatable {
    let reference: String
    let barkEventID: String?

    init?(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == "rjtracker", components.host == "tracker",
              components.path.isEmpty, components.user == nil, components.password == nil,
              components.port == nil, components.fragment == nil,
              let reference = components.queryItems?.first(where: { $0.name == "ref" })?.value,
              let separator = reference.firstIndex(of: ":"),
              ["apple", "google", "samsung", "fusion"].contains(String(reference[..<separator])),
              !reference[reference.index(after: separator)...].isEmpty,
              reference.count <= 512, !reference.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
        else { return nil }
        self.reference = reference
        if components.queryItems?.contains(where: { $0.name == "alarm" && $0.value == "1" }) == true,
           let event = components.queryItems?.first(where: { $0.name == "event" })?.value,
           event.range(of: "^evt_[0-9]+_[0-9a-f]{12}$", options: .regularExpression) != nil {
            barkEventID = event
        } else {
            barkEventID = nil
        }
    }
}
