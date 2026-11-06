import SwiftUI
import MapKit

struct TrackerDashboardShell: View {
    @Environment(AppModel.self) private var model
    @State private var path: [String] = []
    var body: some View {
        TabView {
            NavigationStack(path: $path) {
                TrackerLibraryView { tracker in path.append(tracker.ref) }
                    .navigationDestination(for: String.self) { ref in
                        if let tracker = model.trackers.first(where: { $0.ref == ref }) {
                            TrackerDetailView(tracker: tracker)
                        } else {
                            ContentUnavailableView("Objekt nicht verfügbar", systemImage: "airtag")
                        }
                    }
            }.tabItem { Label("Objekte", systemImage: "square.grid.2x2.fill") }
            NavigationStack { if model.serverActionsAvailable { PlacesHomeView() } else { ServerRequiredView() } }
                .tabItem { Label("Orte", systemImage: "mappin.and.ellipse") }
            NavigationStack { if model.serverActionsAvailable { AlertsView() } else { ServerRequiredView() } }
                .tabItem { Label("Meldungen", systemImage: "bell") }.badge(model.bootstrap?.alerts?.unreadCount ?? 0)
            NavigationStack { MoreView() }.tabItem { Label("Ich", systemImage: "person.crop.circle") }
        }
        .alert("RJ Tracker", isPresented: Binding(get: { model.errorMessage != nil || model.locationService.message != nil }, set: { if !$0 { model.errorMessage = nil; model.locationService.message = nil } })) {
            Button("OK") { model.errorMessage = nil; model.locationService.message = nil }
        } message: { Text(model.errorMessage ?? model.locationService.message ?? "") }
    }
}

struct DashboardShortcut: View {
    let title: String
    let symbol: String
    let tint: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: symbol).font(.title2).foregroundStyle(tint)
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, minHeight: 65, alignment: .leading).rjCard()
    }
}

struct SchoolBagHub: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                RJSectionTitle(title: "Die Schulwoche im Blick", subtitle: "Ankunft, bestätigte Aufenthalte und Meldungen pro Tasche", symbol: "backpack.fill")
                if model.bootstrap?.session?.user?.isMainAdmin != true {
                    ContentUnavailableView("Hauptadmin-Anmeldung erforderlich", systemImage: "lock.shield")
                } else {
                    Text("Wähle einen Server-Tracker für seinen Tagesplan und die Wochenübersicht.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 14)], spacing: 14) {
                        ForEach(model.bootstrap?.trackers ?? []) { tracker in
                            NavigationLink { SchoolPlanView(tracker: tracker) } label: {
                                TrackerListRow(tracker: tracker).rjCard()
                            }.buttonStyle(.plain).accessibilityIdentifier("school-bag-\(tracker.ref)")
                        }
                    }
                }
            }.padding(20).frame(maxWidth: 1100).frame(maxWidth: .infinity)
        }.rjScreenChrome().navigationTitle("Schultaschen").navigationBarTitleDisplayMode(.inline)
    }
}

struct TrackerMapOverview: View {
    @Environment(AppModel.self) private var model
    @State private var position: MapCameraPosition = .automatic
    @State private var selected: Tracker?
    @State private var satellite = false
    private var located: [Tracker] { model.filteredTrackers.filter { $0.validLocation != nil } }
    var body: some View {
        Map(position: $position) {
            UserAnnotation()
            ForEach(located) { tracker in
                if let fix = tracker.validLocation {
                    Annotation(tracker.name, coordinate: fix.coordinate, anchor: .bottom) {
                        Button { selected = tracker } label: {
                            TrackerMapBubble(tracker: tracker, selected: false, locating: model.isLocating(tracker))
                        }.buttonStyle(.plain).accessibilityLabel("\(tracker.name) auf Karte öffnen")
                    }
                }
            }
        }
        .mapStyle(satellite ? .hybrid(elevation: .realistic) : .standard(pointsOfInterest: .excludingAll))
        .mapControls { MapCompass(); MapScaleView() }
        .overlay {
            if located.isEmpty {
                ContentUnavailableView("Noch keine Standorte", systemImage: "map", description: Text("Gespeicherte Ortungen erscheinen hier, sobald sie verfügbar sind."))
                    .rjCard().padding()
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Label("\(located.count) gespeicherte Standorte", systemImage: "clock.arrow.circlepath").font(.caption)
                Spacer()
                Button("Alle zeigen", systemImage: "arrow.up.left.and.arrow.down.right") { fit() }
                    .labelStyle(.iconOnly).buttonStyle(.bordered).accessibilityIdentifier("dashboard-map-fit")
            }.padding(14).background(.regularMaterial)
        }
        .navigationTitle("Karte").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Toggle("Satellit", isOn: $satellite).toggleStyle(.button)
            Button("Meine Position", systemImage: "location") {
                model.locationService.request()
                position = .userLocation(fallback: .automatic)
            }
        }
        .task { fit() }
        .sheet(item: $selected) { tracker in
            NavigationStack {
                TrackerDetailView(tracker: tracker)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fertig") { selected = nil } } }
            }
        }
    }
    private func fit() {
        if let region = RJMapCamera.overview(locations: located.compactMap(\.validLocation), panelCoverage: 0) {
            position = .region(region)
        }
    }
}
