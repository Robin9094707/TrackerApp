import SwiftUI
import MapKit

struct TrackerHomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var position: MapCameraPosition = .automatic
    @State private var selectedRef: String?
    @State private var path: [String] = []
    @State private var tab = 0
    @State private var detent: PresentationDetent = .medium
    @State private var follow = true
    @AppStorage("mapAppearance") private var mapAppearance = "standard"
    @AppStorage("showMapZones") private var showZones = false

    private var current: Tracker? { model.trackers.first { $0.ref == selectedRef } }
    private var located: [Tracker] { model.filteredTrackers.filter { $0.validLocation != nil } }
    private var coverage: CGFloat { sizeClass == .regular ? 0 : (detent == .large ? 0.80 : detent == .medium ? 0.48 : 0.22) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            map
            if sizeClass == .regular {
                inspector
                    .frame(width: 380)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28))
                    .clipShape(RoundedRectangle(cornerRadius: 28))
                    .shadow(color: .black.opacity(0.12), radius: 18, y: 8)
                    .padding(16)
            }
        }
        .sheet(isPresented: Binding(get: { sizeClass != .regular }, set: { _ in })) {
            inspector
                .presentationDetents([.height(190), .medium, .large], selection: $detent)
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
                .presentationBackgroundInteraction(.enabled(upThrough: .large))
                .interactiveDismissDisabled()
        }
        .onChange(of: current?.location) { _, _ in if follow { focusCurrent() } }
        .onChange(of: detent) { _, value in
            if value != .large, follow { focusCurrent() }
        }
        .onChange(of: model.locationService.location) { _, value in
            guard let value, selectedRef == nil else { return }
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
            VStack(spacing: 12) {
                Menu {
                    Picker("Kartenansicht", selection: $mapAppearance) {
                        Text("Standard").tag("standard")
                        Text("Satellit").tag("hybrid")
                        Text("Nahverkehr").tag("transit")
                    }
                    Toggle("Orte und Geofences", isOn: $showZones)
                } label: { Image(systemName: "map").rjGlassControl() }
                .accessibilityLabel("Kartenoptionen")
                Button {
                    selectedRef = nil
                    path = []
                    follow = false
                    animate { position = .automatic }
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
                        } else {
                            ContentUnavailableView("Objekt nicht verfügbar", systemImage: "airtag", description: Text("Es wurde entfernt oder ist für dieses Konto nicht sichtbar."))
                        }
                    }
            }
            .tabItem { Label("Objekte", systemImage: "airtag.radiowaves.forward") }.tag(0)
            NavigationStack { PlacesHomeView() }
                .tabItem { Label("Orte", systemImage: "mappin.and.ellipse") }.tag(1)
            NavigationStack { AlertsView() }
                .tabItem { Label("Meldungen", systemImage: "bell") }
                .badge(model.bootstrap?.alerts?.unreadCount ?? 0).tag(2)
            NavigationStack { MoreView() }
                .tabItem { Label("Ich", systemImage: "person.crop.circle") }.tag(3)
        }
        .onChange(of: tab) { _, value in
            if value != 0 { detent = .large }
            else { detent = .medium }
        }
        .alert("RJ Tracker", isPresented: Binding(get: { model.errorMessage != nil || model.locationService.message != nil }, set: { if !$0 { model.errorMessage = nil; model.locationService.message = nil } })) {
            Button("OK") { model.errorMessage = nil; model.locationService.message = nil }
        } message: { Text(model.errorMessage ?? model.locationService.message ?? "") }
    }

    private func select(_ tracker: Tracker) {
        selectedRef = tracker.ref
        tab = 0
        path = [tracker.ref]
        detent = .medium
        follow = true
        focusCurrent()
        Haptics.impact()
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
    @Environment(AppModel.self) private var model
    let onSelect: (Tracker) -> Void

    var body: some View {
        @Bindable var model = model
        List {
            Section {
                SyncStatusView()
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                if let message = model.statusMessage {
                    HStack(alignment: .top) {
                        Text(message).font(.footnote).foregroundStyle(.secondary)
                        Spacer()
                        Button { model.statusMessage = nil } label: { Image(systemName: "xmark.circle.fill") }
                            .accessibilityLabel("Hinweis schließen")
                    }
                }
                if model.filteredTrackers.isEmpty {
                    ContentUnavailableView(model.trackers.isEmpty ? "Noch keine Objekte" : "Keine Treffer", systemImage: "airtag", description: Text(model.trackers.isEmpty ? "Füge Tracker in deinem Web Studio hinzu und aktualisiere diese Liste." : "Passe deine Suche oder Filter an."))
                }
                ForEach(model.filteredTrackers) { tracker in
                    Button { onSelect(tracker) } label: { TrackerListRow(tracker: tracker) }
                        .buttonStyle(.plain)
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
                if model.selectedScope != .all || model.providerFilter != "all" {
                    Text("\(model.selectedScope.title) · \(model.providerFilter == "all" ? "Alle Netze" : model.providerFilter.rjProviderName)")
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .navigationTitle("Objekte")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $model.searchText, prompt: "Name, Adresse oder Notiz")
        .refreshable { await model.refresh() }
        .toolbar {
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
                    Button("Filter zurücksetzen") {
                        model.selectedScope = .all; model.providerFilter = "all"; model.selectedGroup = nil; model.searchText = ""
                    }
                } label: { Image(systemName: "line.3.horizontal.decrease") }
                .accessibilityLabel("Filter und Sortierung")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { Task { await model.locateAll() } } label: {
                    if model.isLocatingAll { ProgressView() } else { Image(systemName: "arrow.clockwise") }
                }
                .disabled(model.isLocatingAll || !model.locatingRefs.isEmpty || model.trackers.isEmpty)
                .accessibilityLabel("Alle Tracker orten")
            }
        }
        .onChange(of: model.selectedSort) { _, sort in
            if sort == .nearest { model.locationService.request() }
        }
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
            Text(tracker.emoji ?? "📍").font(.system(size: 30))
                .frame(width: 54, height: 54)
                .background(tracker.provider.rjProviderColor.opacity(0.08), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Text(tracker.name).font(.headline).foregroundStyle(.primary)
                    if tracker.favorite == true { Image(systemName: "star.fill").font(.caption2).foregroundStyle(.orange) }
                }
                ResolvedAddressText(location: tracker.validLocation, fallback: tracker.location == nil ? "Kein Standort" : "Adresse nicht verfügbar")
                    .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                HStack(spacing: 6) {
                    FreshnessLabel(timestamp: tracker.reportTimestamp > 0 ? tracker.reportTimestamp : nil)
                    Text("· \(tracker.latestSourceName?.rjProviderName ?? tracker.provider.rjProviderName)")
                        .font(.caption).foregroundStyle(.secondary)
                    if let origin = model.locationService.location, let distance = tracker.distance(from: origin) {
                        Text("· \(distance.metersText)").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer(minLength: 0)
            if model.isLocating(tracker) { ProgressView().controlSize(.small) }
            else { Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary) }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

struct SyncStatusView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        HStack(spacing: 6) {
            if model.isRefreshing { ProgressView().controlSize(.mini) }
            else { Image(systemName: model.refreshError == nil ? "checkmark.icloud" : "wifi.exclamationmark") }
            VStack(alignment: .leading, spacing: 2) {
                if let date = model.lastRefresh {
                    Text("\(model.trackers.count) Objekte · Stand \(date.formatted(date: .omitted, time: .shortened))")
                } else { Text("Daten werden geladen …") }
                if model.refreshError != nil { Text("Server nicht erreichbar. Letzter Stand wird angezeigt.").foregroundStyle(.orange) }
            }
            Spacer()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityIdentifier("sync-status")
    }
}
