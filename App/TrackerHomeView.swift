import SwiftUI
import MapKit
import SpotIntegration

struct TrackerLibraryView: View {
    @ObservedObject private var google = GoogleTrackerStore.shared
    @Environment(AppModel.self) private var model
    let onSelect: (Tracker) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var addingObject = false

    var body: some View {
        @Bindable var model = model
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("DEIN TRACKER-PANEL").font(.caption.weight(.bold)).tracking(2).foregroundStyle(Color.accentColor)
                    Text("Alles im Blick.").font(.system(.largeTitle, design: .rounded, weight: .bold))
                    Text("\(model.trackers.count) Objekte · \(model.trackers.filter { $0.validLocation != nil }.count) mit gespeichertem Standort")
                        .font(.subheadline).foregroundStyle(.secondary)
                }.padding(.top, 8)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 10)], spacing: 10) {
                    NavigationLink { TrackerMapOverview() } label: { DashboardShortcut(title: "Karte", symbol: "map.fill", tint: .teal) }
                    if model.serverActionsAvailable {
                        NavigationLink { SchoolBagHub() } label: { DashboardShortcut(title: "Schultaschen", symbol: "backpack.fill", tint: .purple) }
                        NavigationLink { BarkSettingsView() } label: { DashboardShortcut(title: "Bark", symbol: "bell.badge.fill", tint: .orange) }
                    }
                }.buttonStyle(.plain)
                if let message = model.statusMessage {
                    HStack(alignment: .top) {
                        Text(message).font(.footnote).foregroundStyle(.secondary)
                        Spacer()
                        Button { model.statusMessage = nil } label: { Image(systemName: "xmark.circle.fill") }
                            .accessibilityLabel("Hinweis schließen")
                    }.rjCard()
                }
                HStack {
                    Text("Meine Objekte").font(.title2.bold())
                    Spacer()
                    Text("\(model.filteredTrackers.count)").font(.headline).foregroundStyle(Color.accentColor)
                }
                if model.selectedScope != .all || model.providerFilter != "all" {
                    Text("\(model.selectedScope.title) · \(model.providerFilter == "all" ? "Alle Netze" : model.providerFilter.rjProviderName)")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                if model.trackers.isEmpty && (model.connectionState == .restoring || model.isRefreshing) {
                    ProgressView("Objekte werden geladen …").frame(maxWidth: .infinity).padding()
                } else if model.filteredTrackers.isEmpty {
                    ContentUnavailableView(model.trackers.isEmpty ? "Noch keine Objekte" : "Keine Treffer", systemImage: "airtag", description: Text(model.trackers.isEmpty ? "Füge über + deine Tracker hinzu." : "Passe deine Suche oder Filter an."))
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 290), spacing: 14)], spacing: 14) {
                    ForEach(model.filteredTrackers) { tracker in
                        Button { onSelect(tracker) } label: { TrackerListRow(tracker: tracker).rjCard() }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("tracker-row-\(tracker.ref)")
                            .contextMenu {
                                Button { Task { await model.setFavorite(tracker) } } label: {
                                    Label(tracker.favorite == true ? "Favorit entfernen" : "Als Favorit sichern", systemImage: "star")
                                }
                                Button { Task { await model.locate(tracker) } } label: { Label("Orten", systemImage: "location.fill") }
                                if tracker.validLocation != nil { ShareLink(item: tracker.shareText) { Label("Standort teilen", systemImage: "square.and.arrow.up") } }
                            }
                    }
                }
                SyncStatusView().rjCard()
            }.padding(20).padding(.bottom, 24).frame(maxWidth: 1100).frame(maxWidth: .infinity)
        }
        .rjScreenChrome()
        .navigationTitle("Objekte")
        .navigationBarTitleDisplayMode(.inline)
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
            Text(tracker.emoji ?? "📍").font(.system(size: 30))
                .frame(width: 54, height: 54)
                .background(Color(uiColor: .tertiarySystemFill), in: Circle())
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: tracker.provider.rjProviderSymbol)
                        .font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                        .background(tracker.provider.rjProviderColor.gradient, in: Circle())
                        .overlay(Circle().stroke(Color(uiColor: .systemGroupedBackground), lineWidth: 2))
                        .offset(x: 2, y: 2)
                        .accessibilityHidden(true)
                }
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 5) {
                    Text(tracker.name).font(.system(.headline, design: .default).weight(.semibold)).foregroundStyle(.primary).lineLimit(2)
                    if tracker.favorite == true { Image(systemName: "star.fill").font(.caption2).foregroundStyle(.orange) }
                }
                HStack(spacing: 4) {
                    Text(tracker.location?.address?.locality ?? tracker.provider.rjProviderName)
                    Text("·")
                    FreshnessLabel(timestamp: tracker.reportTimestamp > 0 ? tracker.reportTimestamp : nil)
                }.font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
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
        }.font(.caption).foregroundStyle(.secondary).padding(.vertical, 4)
            .accessibilityElement(children: .contain)
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

