import SwiftUI
import MapKit

struct TrackerDashboardShell: View {
    @Environment(AppModel.self) private var model
    @Binding var trackerLink: TrackerPushLink?
    @State private var path: [String] = []
    @State private var tab = 0
    @State private var activeLink: TrackerPushLink?

    var body: some View {
        TabView(selection: $tab) {
            Tab("Objekte", systemImage: "square.grid.2x2.fill", value: 0) {
                NavigationStack(path: $path) {
                    TrackerLibraryView { tracker in
                        activeLink = nil
                        path.append(tracker.ref)
                    }
                        .navigationDestination(for: String.self) { ref in
                            if let tracker = model.trackers.first(where: { $0.ref == ref }) {
                                TrackerDetailView(tracker: tracker, barkEventID: activeLink?.reference == ref ? activeLink?.barkEventID : nil)
                                    .id(activeLink?.barkEventID ?? ref)
                            } else {
                                ContentUnavailableView("Objekt nicht verfügbar", systemImage: "airtag")
                            }
                        }
                }
            }
            Tab("Orte", systemImage: "mappin.and.ellipse", value: 1) {
                NavigationStack { if model.serverActionsAvailable { PlacesHomeView() } else { ServerRequiredView() } }
            }
            Tab("Meldungen", systemImage: "bell", value: 2) {
                NavigationStack { if model.serverActionsAvailable { AlertsView() } else { ServerRequiredView() } }
            }
            .badge(model.bootstrap?.alerts?.unreadCount ?? 0)
            Tab("Ich", systemImage: "person.crop.circle", value: 3) {
                NavigationStack { MoreView() }
            }
            Tab("Suchen", systemImage: "magnifyingglass", value: 4, role: .search) {
                NavigationStack { TrackerSearchView() }
            }
        }
        .rjTabBarMinimizeOnScroll()
        .rjTabAccessory { RJStatusAccessory() }
        .onChange(of: trackerLink, initial: true) { _, link in
            guard let link else { return }
            activeLink = link
            tab = 0
            path = [link.reference]
            trackerLink = nil
            if !model.trackers.contains(where: { $0.ref == link.reference }) {
                Task { await model.refreshTrackers() }
            }
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
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: symbol).font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(tint.gradient, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                .shadow(color: tint.opacity(0.35), radius: 8, x: 0, y: 4)
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                .lineLimit(1).minimumScaleFactor(0.75)
        }.frame(maxWidth: .infinity, minHeight: 70, alignment: .leading).rjCard(interactive: true)
    }
}

struct SchoolBagHub: View {
    @Environment(AppModel.self) private var model

    private static func fusionFirst(_ lhs: Tracker, _ rhs: Tracker) -> Bool {
        let left = lhs.provider == "fusion" ? 0 : 1
        let right = rhs.provider == "fusion" ? 0 : 1
        if left != right { return left < right }
        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                RJSectionTitle(title: "Die Schulwoche im Blick", subtitle: "Ankunft, bestätigte Aufenthalte und Meldungen pro Tasche", symbol: "backpack.fill")
                if model.bootstrap?.session?.user?.isMainAdmin != true {
                    ContentUnavailableView("Hauptadmin-Anmeldung erforderlich", systemImage: "lock.shield")
                } else {
                    let all = (model.bootstrap?.trackers ?? []).filter { $0.archived != true }
                    let bags = all.filter { $0.schoolBag == true }
                    let others = all.filter { $0.schoolBag != true }.sorted(by: Self.fusionFirst)
                    Text("Jedes Objekt kann eine Tasche sein – auch Fusionen aus Apple, Google und Samsung. Tippe für Tagesplan und Wochenübersicht.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    if !bags.isEmpty {
                        Text("Aktive Taschen").font(.footnote.weight(.bold)).foregroundStyle(.secondary).textCase(.uppercase)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 14)], spacing: 14) {
                            ForEach(bags) { tracker in
                                VStack(spacing: 10) {
                                    NavigationLink { SchoolPlanView(tracker: tracker) } label: {
                                        TrackerListRow(tracker: tracker)
                                    }.buttonStyle(.plain).accessibilityIdentifier("school-bag-\(tracker.ref)")
                                    Divider()
                                    BagToggleButton(tracker: tracker)
                                }.rjCard()
                            }
                        }
                    }
                    Text(bags.isEmpty ? "Objekte" : "Weitere Objekte").font(.footnote.weight(.bold)).foregroundStyle(.secondary).textCase(.uppercase)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 14)], spacing: 14) {
                        ForEach(others) { tracker in
                            VStack(spacing: 10) {
                                NavigationLink { SchoolPlanView(tracker: tracker) } label: {
                                    TrackerListRow(tracker: tracker)
                                }.buttonStyle(.plain).accessibilityIdentifier("school-bag-\(tracker.ref)")
                                Divider()
                                BagToggleButton(tracker: tracker)
                            }.rjCard()
                        }
                    }
                }
            }.padding(20).frame(maxWidth: 1100).frame(maxWidth: .infinity)
        }.rjScreenChrome().navigationTitle("Schultaschen").navigationBarTitleDisplayMode(.inline)
    }
}

struct TrackerMapOverview: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var position: MapCameraPosition = .automatic
    @State private var selected: Tracker?
    @State private var satellite = false
    @State private var actionsOpen = false
    @Namespace private var glass
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
        .overlay(alignment: .topTrailing) {
            RJMapControlStack {
                RJMapControlButton(symbol: satellite ? "map" : "globe.europe.africa", active: satellite, label: satellite ? "Standardkarte" : "Satellit") {
                    satellite.toggle()
                }
                RJMapControlDivider()
                RJMapControlButton(symbol: "location", label: "Meine Position") {
                    model.locationService.request()
                    position = .userLocation(fallback: .automatic)
                }
            }.padding(12)
        }
        .overlay {
            if located.isEmpty {
                ContentUnavailableView("Noch keine Standorte", systemImage: "map", description: Text("Gespeicherte Ortungen erscheinen hier, sobald sie verfügbar sind."))
                    .rjCard().padding()
            }
        }
        .rjSafeAreaBar(edge: .bottom) { bottomBar }
        .navigationTitle("Karte").navigationBarTitleDisplayMode(.inline)
        .task { fit() }
        .sheet(item: $selected) { tracker in
            NavigationStack {
                TrackerDetailView(tracker: tracker)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fertig") { selected = nil } } }
            }
            .presentationDetents([.medium, .large])
            .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        }
    }

    /// Floating glass: status capsule and fit button merge into one surface,
    /// the action button morphs open into extra actions (glassEffectID).
    private var bottomBar: some View {
        RJGlassGroup(spacing: 14) {
            HStack(alignment: .bottom, spacing: 10) {
                HStack(spacing: 10) {
                    Label("\(located.count) Standorte", systemImage: "clock.arrow.circlepath")
                        .font(.subheadline.weight(.semibold))
                        .padding(.leading, 16).padding(.vertical, 12)
                    Button { fit() } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.body.weight(.semibold))
                            .frame(width: 44, height: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Alle zeigen")
                    .accessibilityIdentifier("dashboard-map-fit")
                    .padding(.trailing, 4)
                }
                .rjGlassSurface(Capsule(), interactive: true)
                .rjGlassID("status", in: glass)
                Spacer(minLength: 0)
                VStack(spacing: 10) {
                    if actionsOpen {
                        if model.serverActionsAvailable {
                            RJGlassIconButton(symbol: "location.fill", label: "Alle orten", size: 48) {
                                Task { await model.locateAll() }
                                toggleActions()
                            }
                            .disabled(model.isLocatingAll)
                            .rjGlassID("locate-all", in: glass)
                        }
                        RJGlassIconButton(symbol: "arrow.clockwise", label: "Aktualisieren", size: 48) {
                            Task { await model.refreshTrackers() }
                            toggleActions()
                        }
                        .rjGlassID("refresh", in: glass)
                    }
                    RJGlassIconButton(symbol: actionsOpen ? "xmark" : "ellipsis", label: actionsOpen ? "Aktionen schließen" : "Weitere Aktionen",
                                      tint: actionsOpen ? nil : Color.accentColor, size: 52) { toggleActions() }
                        .rjGlassID("actions", in: glass)
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 8)
        }
    }

    private func toggleActions() {
        withAnimation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.78)) { actionsOpen.toggle() }
    }

    private func fit() {
        if let region = RJMapCamera.overview(locations: located.compactMap(\.validLocation), panelCoverage: 0) {
            position = .region(region)
        }
    }
}
