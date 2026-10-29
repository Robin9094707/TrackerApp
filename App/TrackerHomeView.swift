import SwiftUI
import MapKit
import SpotIntegration

struct TrackerHomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var google = GoogleTrackerStore.shared
    @State private var position: MapCameraPosition = .automatic
    @State private var selectedRef: String?
    @State private var path: [String] = []
    @State private var tab = 0
    @State private var detent: PresentationDetent = .fraction(0.60)
    @State private var follow = true
    @AppStorage("mapAppearance") private var mapAppearance = "standard"
    @AppStorage("showMapZones") private var showZones = false

    private var current: Tracker? { model.trackers.first { $0.ref == selectedRef } }
    private var located: [Tracker] { model.filteredTrackers.filter { $0.validLocation != nil } }
    private var coverage: CGFloat { sizeClass == .regular ? 0 : (detent == .large ? 0.80 : detent == .fraction(0.60) ? 0.60 : 0.22) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            map
            if sizeClass == .regular {
                inspector
                    .frame(width: 380)
                    .background(Color(uiColor: .systemGroupedBackground), in: RoundedRectangle(cornerRadius: 28))
                    .clipShape(RoundedRectangle(cornerRadius: 28))
                    .shadow(color: .black.opacity(0.12), radius: 18, y: 8)
                    .padding(16)
            }
        }
        .sheet(isPresented: Binding(get: { sizeClass != .regular }, set: { _ in })) {
            inspector
                .presentationDetents([.height(190), .fraction(0.60), .large], selection: $detent)
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
                .presentationBackground(Color(uiColor: .systemGroupedBackground))
                .presentationBackgroundInteraction(.enabled(upThrough: .large))
                .interactiveDismissDisabled()
        }
        .task { fitAll(); await google.restoreIfNeeded() }
        .onChange(of: google.trackers.map(\.id)) { _, _ in if selectedRef == nil && follow { fitAll() } }
        .onChange(of: located.compactMap(\.validLocation)) { _, _ in if selectedRef == nil && follow { fitAll() } }
        .onChange(of: current?.location) { _, _ in if follow { focusCurrent() } }
        .onChange(of: detent) { _, value in
            if value != .large { if selectedRef == nil { fitAll() } else if follow { focusCurrent() } }
        }
        .onChange(of: model.locationService.location) { _, value in
            guard let value, selectedRef == nil, follow else { return }
            animate { position = .region(MKCoordinateRegion(center: value.coordinate, latitudinalMeters: 1500, longitudinalMeters: 1500)) }
        }
        .onChange(of: path) { _, value in
            selectedRef = value.last
            follow = true
            if selectedRef != nil { focusCurrent() }
        }
    }

    private var map: some View {
        Map(position: $position) {
            UserAnnotation()
            ForEach(located) { tracker in
                if let location = tracker.validLocation {
                    if selectedRef == tracker.ref, let accuracy = location.accuracyM, accuracy > 0 {
                        MapCircle(center: location.coordinate, radius: min(accuracy, 100_000))
                            .foregroundStyle(.blue.opacity(0.10))
                            .stroke(.blue.opacity(0.35), lineWidth: 1)
                    }
                    Annotation(tracker.name, coordinate: location.coordinate, anchor: .bottom) {
                        Button { select(tracker) } label: {
                            TrackerMapBubble(tracker: tracker, selected: selectedRef == tracker.ref, locating: model.isLocating(tracker))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(tracker.name) auf Karte öffnen")
                    }
                }
            }
            if showZones {
                ForEach(model.bootstrap?.geofences ?? []) { fence in
                    MapCircle(center: fence.center.coordinate, radius: fence.radiusM ?? 100)
                        .foregroundStyle(.purple.opacity(0.08))
                        .stroke(.purple.opacity(0.35), lineWidth: 1)
                }
                ForEach(model.bootstrap?.savedPlaces ?? []) { place in
                    if let lat = place.latitude, let lon = place.longitude {
                        Marker(place.label, systemImage: "star.fill", coordinate: .init(latitude: lat, longitude: lon)).tint(.orange)
                    }
                }
            }
        }
        .mapStyle(mapStyle)
        .mapControls { MapCompass(); MapScaleView() }
        .onMapCameraChange(frequency: .onEnd) { _ in
            if position.positionedByUser { follow = false }
        }
        .ignoresSafeArea()
        .safeAreaInset(edge: .top, alignment: .trailing) {
            RJGlassControls {
            VStack(spacing: 12) {
                Menu {
                    Picker("Kartenansicht", selection: $mapAppearance) {
                        Text("Standard").tag("standard")
                        Text("Satellit").tag("hybrid")
                        Text("Haltestellen").tag("transit")
                    }
                    Toggle("Orte und Geofences", isOn: $showZones)
                } label: { Image(systemName: "map").rjGlassControl() }
                .accessibilityLabel("Kartenoptionen")
                Button {
                    selectedRef = nil
                    path = []
                    follow = false
                    fitAll()
                } label: { Image(systemName: "arrow.up.left.and.arrow.down.right").rjGlassControl() }
                .accessibilityLabel("Alle Objekte zeigen")
                Button {
                    selectedRef = nil
                    path = []
                    model.locationService.request()
                } label: { Image(systemName: "location").rjGlassControl() }
                .accessibilityLabel("Meine Position")
                if current != nil {
                    Button { follow.toggle(); if follow { focusCurrent() } } label: {
                        Image(systemName: follow ? "scope" : "viewfinder").rjGlassControl()
                    }
                    .accessibilityLabel(follow ? "Tracker nicht mehr folgen" : "Tracker folgen")
                    .tint(follow ? .blue : .primary)
                }
            }
            .font(.title3)
            .buttonStyle(.plain)
            .padding(.trailing, 16)
            .padding(.top, 8)
            }
        }
    }

    private var mapStyle: MapStyle {
        switch mapAppearance {
        case "hybrid": .hybrid(elevation: .realistic)
        case "transit": .standard(pointsOfInterest: .including([.publicTransport]))
        default: .standard(elevation: .realistic, pointsOfInterest: .excludingAll)
        }
    }

    private var inspector: some View {
        TabView(selection: $tab) {
            NavigationStack(path: $path) {
                TrackerLibraryView(onSelect: select)
                    .navigationDestination(for: String.self) { ref in
                        if let tracker = model.trackers.first(where: { $0.ref == ref }) {
                            TrackerDetailView(tracker: tracker)
                                .toolbar {
                                    ToolbarItem(placement: .topBarTrailing) {
                                        Button { path = []; selectedRef = nil; fitAll() } label: { Image(systemName: "xmark") }
                                            .accessibilityLabel("Objekt schließen")
                                    }
                                }
                        } else {
                            ContentUnavailableView("Objekt nicht verfügbar", systemImage: "airtag", description: Text("Es wurde entfernt oder ist für dieses Konto nicht sichtbar."))
                        }
                    }
            }
            .tabItem { Label("Objekte", systemImage: "airtag.radiowaves.forward") }.tag(0)
            NavigationStack { if model.serverActionsAvailable { PlacesHomeView() } else { ServerRequiredView() } }
                .tabItem { Label("Orte", systemImage: "mappin.and.ellipse") }.tag(1)
            NavigationStack { if model.serverActionsAvailable { AlertsView() } else { ServerRequiredView() } }
                .tabItem { Label("Meldungen", systemImage: "bell") }
                .badge(model.bootstrap?.alerts?.unreadCount ?? 0).tag(2)
            NavigationStack { MoreView() }
                .tabItem { Label("Ich", systemImage: "person.crop.circle") }.tag(3)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .toolbarBackground(Color(uiColor: .systemGroupedBackground), for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .environment(\.rjExpandInspector, { detent = .large })
        .onChange(of: tab) { _, value in
            if value != 0 { detent = .large }
            else { detent = .fraction(0.60) }
        }
        .alert("RJ Tracker", isPresented: Binding(get: { model.errorMessage != nil || model.locationService.message != nil }, set: { if !$0 { model.errorMessage = nil; model.locationService.message = nil } })) {
            Button("OK") { model.errorMessage = nil; model.locationService.message = nil }
        } message: { Text(model.errorMessage ?? model.locationService.message ?? "") }
    }

    private func select(_ tracker: Tracker) {
        selectedRef = tracker.ref
        tab = 0
        path = [tracker.ref]
        detent = .fraction(0.60)
        follow = true
        focusCurrent()
        Haptics.impact()
    }

    private func fitAll() {
        guard let region = RJMapCamera.overview(locations: located.compactMap(\.validLocation), panelCoverage: coverage) else { return }
        animate { position = .region(region) }
    }

    private func focusCurrent() {
        guard let location = current?.validLocation else { return }
        animate { position = .region(RJMapCamera.focusedRegion(for: location, panelCoverage: coverage)) }
    }

    private func animate(_ change: () -> Void) {
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.35), change)
    }
}

struct TrackerLibraryView: View {
    @ObservedObject private var google = GoogleTrackerStore.shared
    @Environment(AppModel.self) private var model
    let onSelect: (Tracker) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var addingObject = false

    var body: some View {
        @Bindable var model = model
        List {
            Section {
                if let message = model.statusMessage {
                    HStack(alignment: .top) {
                        Text(message).font(.footnote).foregroundStyle(.secondary)
                        Spacer()
                        Button { model.statusMessage = nil } label: { Image(systemName: "xmark.circle.fill") }
                            .accessibilityLabel("Hinweis schließen")
                    }
                }
                if model.trackers.isEmpty && (model.connectionState == .restoring || model.isRefreshing) {
                    HStack(spacing: 10) { ProgressView(); Text("Objekte werden geladen …").foregroundStyle(.secondary) }
                        .listRowBackground(Color.clear)
                } else if model.filteredTrackers.isEmpty {
                    ContentUnavailableView(model.trackers.isEmpty ? "Noch keine Objekte" : "Keine Treffer", systemImage: "airtag", description: Text(model.trackers.isEmpty ? "Füge unter Ich → Accounts, Import & Fusionen deine Tracker hinzu." : "Passe deine Suche oder Filter an."))
                }
                ForEach(model.filteredTrackers) { tracker in
                    Button { onSelect(tracker) } label: { TrackerListRow(tracker: tracker) }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 10, leading: 22, bottom: 10, trailing: 22))
                        .alignmentGuide(.listRowSeparatorLeading) { _ in 70 }
                        .accessibilityIdentifier("tracker-row-\(tracker.ref)")
                        .swipeActions(edge: .leading) {
                            Button { Task { await model.setFavorite(tracker) } } label: {
                                Label(tracker.favorite == true ? "Entfernen" : "Favorit", systemImage: "star.fill")
                            }.tint(.orange)
                        }
                        .swipeActions(edge: .trailing) {
                            Button { Task { await model.locate(tracker) } } label: { Label("Orten", systemImage: "location.fill") }.tint(.blue)
                        }
                        .contextMenu {
                            Button { Task { await model.setFavorite(tracker) } } label: {
                                Label(tracker.favorite == true ? "Favorit entfernen" : "Als Favorit sichern", systemImage: "star")
                            }
                            if tracker.validLocation != nil { ShareLink(item: tracker.shareText) { Label("Standort teilen", systemImage: "square.and.arrow.up") } }
                        }
                }
            } header: {
                Text("Meine Objekte").font(.title3.weight(.semibold)).textCase(nil).padding(.vertical, 8)
                if model.selectedScope != .all || model.providerFilter != "all" {
                    Text("\(model.selectedScope.title) · \(model.providerFilter == "all" ? "Alle Netze" : model.providerFilter.rjProviderName)")
                }
            }
            Section {
                SyncStatusView().listRowSeparator(.hidden).listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(RJGlassBackdrop())
        .navigationTitle("Objekte")
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $addingObject) {
            NavigationStack {
                Group {
                    if model.serverActionsAvailable { ProviderSetupView() }
                    else { GoogleAccountView() }
                }
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fertig") { addingObject = false } } }
            }
        }
        .searchable(text: $model.searchText, prompt: "Name, Adresse oder Notiz")
        .refreshable { await refreshVisibleSources() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { addingObject = true } label: { Image(systemName: "plus").font(.title2.weight(.medium)) }
                    .accessibilityLabel("Objekt hinzufügen")
            }
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Picker("Ansicht", selection: $model.selectedScope) {
                        ForEach(TrackerScope.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("Netzwerk", selection: $model.providerFilter) {
                        Text("Alle Netze").tag("all")
                        ForEach(["fusion", "apple", "google", "samsung"], id: \.self) { Text($0.rjProviderName).tag($0) }
                    }
                    Picker("Sortierung", selection: $model.selectedSort) {
                        ForEach(TrackerSort.allCases) { Text($0.title).tag($0) }
                    }
                    if !(model.bootstrap?.trackerGroups ?? []).isEmpty {
                        Picker("Gruppe", selection: $model.selectedGroup) {
                            Text("Alle Gruppen").tag(nil as String?)
                            ForEach(groupOptions, id: \.id) { Text($0.name).tag(Optional($0.id)) }
                        }
                    }
                    Button("Alle Tracker orten") { Task { await model.locateAll() } }
                        .disabled(model.isLocatingAll || !model.locatingRefs.isEmpty)
                    Button("Filter zurücksetzen") {
                        model.selectedScope = .all; model.providerFilter = "all"; model.selectedGroup = nil; model.searchText = ""
                    }
                } label: { Image(systemName: "line.3.horizontal.decrease") }
                .accessibilityLabel("Filter und Sortierung")
            }
            if model.showsGoogleControls {
                ToolbarItem(placement: .topBarTrailing) { GoogleLauncherCard(compact: true) }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { Task { await refreshVisibleSources() } } label: {
                    if model.isRefreshingTrackers || (model.showsGoogleControls && (google.isRefreshing || !google.locating.isEmpty)) { ProgressView() } else { Image(systemName: "arrow.clockwise") }
                }
                .disabled(model.isRefreshingTrackers || (model.showsGoogleControls && (google.isRefreshing || !google.locating.isEmpty)))
                .accessibilityLabel("Standorte aktualisieren")
                .accessibilityIdentifier("refresh-locations")
            }
        }
        .task {
            if model.selectedSort == .nearest { model.locationService.refreshIfAuthorized() }
        }
        .onChange(of: model.selectedSort) { _, sort in
            if sort == .nearest { model.locationService.request() }
        }
    }

    private func refreshVisibleSources() async {
        Haptics.impact()
        // Start the local Google request before waiting for a slow/unreachable server.
        async let local: Void = refreshGoogleIfVisible()
        // A Google-only refresh must not wait for an unrelated offline server.
        if model.connectionState == .connected { await model.refreshTrackers() }
        else if model.providerFilter != "google" || !google.hasCredentials { await model.retryServerConnection() }
        await local
    }
    private func refreshGoogleIfVisible() async {
        if model.showsGoogleControls { await google.refreshLocations() }
    }

    private var groupOptions: [(id: String, name: String)] {
        (model.bootstrap?.trackerGroups ?? []).compactMap { value in
            guard let row = value.objectValue, let id = row["id"]?.stringValue else { return nil }
            return (id, row["name"]?.stringValue ?? row["label"]?.stringValue ?? "Gruppe")
        }
    }
}

struct TrackerListRow: View {
    @Environment(AppModel.self) private var model
    let tracker: Tracker
    var body: some View {
        HStack(spacing: 14) {
            Text(tracker.emoji ?? "📍").font(.system(size: 34))
                .frame(width: 58, height: 58)
                .background(Color(uiColor: .tertiarySystemFill), in: Circle())
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 5) {
                    Text(tracker.name).font(.system(.headline, design: .default).weight(.semibold)).foregroundStyle(.primary).lineLimit(2)
                    if tracker.favorite == true { Image(systemName: "star.fill").font(.caption2).foregroundStyle(.orange) }
                }
                HStack(spacing: 4) {
                    Text(tracker.location?.address?.locality ?? tracker.provider.rjProviderName)
                    Text("·")
                    FreshnessLabel(timestamp: tracker.reportTimestamp > 0 ? tracker.reportTimestamp : nil)
                }.font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 6)
            if model.isLocating(tracker) { ProgressView().controlSize(.small) }
            else if tracker.status == "In der Nähe" {
                Text("Bei dir").font(.subheadline).foregroundStyle(.secondary)
            } else if let origin = model.locationService.location, let distance = tracker.distance(from: origin) {
                Text(distance.metersText).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
    }
}

struct SyncStatusView: View {
    @Environment(AppModel.self) private var model
    @ObservedObject private var google = GoogleTrackerStore.shared
    @State private var retryingServer = false
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if model.showsGoogleControls, google.hasCredentials {
                HStack(spacing: 6) {
                    if google.isRefreshing || !google.locating.isEmpty { ProgressView().controlSize(.mini) }
                    Label(google.isRefreshing ? "Google-Objekte werden geladen …"
                          : (!google.locating.isEmpty ? "Google · warte auf \(google.locating.count) Ortungen …"
                             : "Google direkt auf diesem iPhone · \(google.trackers.count) Objekte"), systemImage: "iphone")
                }
                if let error = google.errorMessage { Text(error).foregroundStyle(.orange) }
            }
            if !model.serverURL.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: model.serverActionsAvailable ? "checkmark.icloud" : "wifi.exclamationmark")
                    if model.isRefreshing || model.isRefreshingTrackers || retryingServer {
                        ProgressView().controlSize(.mini)
                        Text("Server wird aktualisiert …")
                    }
                    else if model.connectionState == .restoring { Text("Server wird verbunden …") }
                    else if model.serverActionsAvailable, let date = model.lastRefresh {
                        Text("Server · Stand \(date.formatted(date: .omitted, time: .shortened))")
                    } else {
                        Text(model.connectionState == .connected ? "Server-Aktualisierung fehlgeschlagen" : "Server nicht verbunden").foregroundStyle(.orange)
                    }
                    Spacer()
                }
                if model.refreshError != nil || model.connectionState == .disconnected {
                    Text("Gespeicherte Standorte bleiben sichtbar. Die Uhrzeit am Objekt zeigt, wann es zuletzt gesehen wurde.")
                    if let error = model.refreshError { Text(error).foregroundStyle(.orange).lineLimit(3) }
                    Button("Erneut verbinden", systemImage: "arrow.clockwise") {
                        retryingServer = true
                        Task {
                            defer { retryingServer = false }
                            if model.connectionState == .connected { await model.refreshTrackers() }
                            else { await model.retryServerConnection() }
                        }
                    }.buttonStyle(.borderless)
                        .disabled(retryingServer || model.isRefreshing || model.isRefreshingTrackers)
                        .accessibilityIdentifier("sync-server-retry")
                }
            }
        }.font(.caption).foregroundStyle(.secondary).padding(.vertical, 4).accessibilityIdentifier("sync-status")
    }
}

struct ServerRequiredView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        ContentUnavailableView {
            Label("Serververbindung erforderlich", systemImage: "network.slash")
        } description: {
            Text("Diese Ansicht benötigt deinen Tracker-Server. Lokal verfügbare Objekte bleiben unter Objekte erreichbar.")
        } actions: {
            Button("Verbindung erneut prüfen") { Task { await model.retryServerConnection() } }
            Button("Server-Anmeldung öffnen") { model.showingServerConnection = true }
        }
    }
}

