import SwiftUI
import MapKit

struct TrackerDetailView: View {
    @Environment(AppModel.self) private var model
    let tracker: Tracker
    @State private var showEdit = false
    @State private var showAutomation = false
    @State private var showSavePlace = false
    @State private var showGeofence = false
    @State private var showRecoveryConfirm = false
    @State private var busy = false
    private var current: Tracker { model.trackers.first { $0.ref == tracker.ref } ?? tracker }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                header
                actions
                if current.provider == "fusion" { FusionSourcesCard(tracker: current) }
                VStack(spacing: 0) {
                    NavigationLink { HistoryView(tracker: current) } label: {
                        detailRow("Standortverlauf", subtitle: current.historyActive == true ? "Aufzeichnung aktiv" : "Gespeicherte Meldungen ansehen", icon: "clock.arrow.circlepath", color: .blue)
                    }
                    Divider().padding(.leading, 48)
                    Button { showAutomation = true } label: {
                        detailRow("Mitteilungen & Verlauf", subtitle: alarmSubtitle, icon: "bell.badge", color: .purple)
                    }
                    Divider().padding(.leading, 48)
                    Button { showSavePlace = true } label: {
                        detailRow("Diesen Ort speichern", subtitle: "Standort als Ort merken", icon: "star", color: .orange)
                    }.disabled(current.validLocation == nil)
                    Divider().padding(.leading, 48)
                    Button { showGeofence = true } label: {
                        detailRow("Bereich überwachen", subtitle: "Geofence an diesem Standort", icon: "mappin.and.ellipse", color: .green)
                    }.disabled(current.validLocation == nil)
                }
                .buttonStyle(.plain).rjCompactCard()
                information
                if ["apple", "fusion"].contains(current.provider) {
                    Button { showRecoveryConfirm = true } label: {
                        Label("Als vermisst suchen", systemImage: "lifepreserver")
                            .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 8)
                    }.buttonStyle(.bordered).tint(.orange).disabled(busy)
                }
            }
            .padding(16)
        }
        .rjScreenChrome()
        .navigationTitle(current.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { showEdit = true } label: { Label("Name & Symbol bearbeiten", systemImage: "pencil") }
                    Button { Task { await model.setFavorite(current) } } label: {
                        Label(current.favorite == true ? "Favorit entfernen" : "Als Favorit sichern", systemImage: "star")
                    }.disabled(model.updatingRefs.contains(current.ref))
                    if current.validLocation != nil {
                        ShareLink(item: current.shareText) { Label("Standort teilen", systemImage: "square.and.arrow.up") }
                    }
                } label: { Image(systemName: "ellipsis") }
                .accessibilityLabel("Objektaktionen")
            }
        }
        .sheet(isPresented: $showEdit) { NavigationStack { TrackerEditorView(tracker: current) } }
        .sheet(isPresented: $showAutomation) { NavigationStack { TrackerAutomationView(tracker: current) } }
        .sheet(isPresented: $showSavePlace) { NavigationStack { PlaceEditorView(seed: current.validLocation, suggestedName: current.name) } }
        .sheet(isPresented: $showGeofence) { NavigationStack { PlaceEditorView(seed: current.validLocation, suggestedName: current.name, geofence: true, trackerRef: current.ref) } }
        .confirmationDialog("Recovery-Suche starten?", isPresented: $showRecoveryConfirm, titleVisibility: .visible) {
            Button("Suche aktivieren") { Task { await recover() } }
        } message: { Text("Der Server legt einen Recovery-Fall an. Dies aktiviert keinen offiziellen Apple-Verloren-Modus.") }
        .refreshable { await model.refresh() }
    }

    private var header: some View {
        VStack(spacing: 10) {
            Text(current.emoji ?? "📍").font(.system(size: 50))
                .frame(width: 86, height: 86)
                .background(current.provider.rjProviderColor.opacity(0.08), in: Circle())
            HStack(spacing: 7) {
                Text(current.name).font(.title2.bold())
                if current.favorite == true { Image(systemName: "star.fill").foregroundStyle(.orange) }
            }
            ResolvedAddressText(location: current.validLocation, fallback: current.location == nil ? "Noch kein Standort gemeldet" : "Adresse nicht verfügbar")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            HStack(spacing: 8) {
                FreshnessLabel(timestamp: current.reportTimestamp > 0 ? current.reportTimestamp : nil)
                if let source = current.latestSourceName { SourceBadge(source: source) }
            }
        }
        .frame(maxWidth: .infinity).padding(.top, 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tracker-detail-header")
    }

    private var actions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { locateButton; routeButton }
            VStack(spacing: 12) { locateButton; routeButton }
        }
    }

    private var locateButton: some View {
        Button { Task { await model.locate(current) } } label: {
            Label(model.isLocating(current) ? "Wird geortet …" : "Jetzt orten", systemImage: "location.fill")
                .font(.headline).frame(maxWidth: .infinity, minHeight: 42)
        }.buttonStyle(.borderedProminent).buttonBorderShape(.roundedRectangle(radius: 18))
            .disabled(model.isLocating(current) || model.isLocatingAll)
    }

    private var routeButton: some View {
        Menu {
            Button("Zu Fuß", systemImage: "figure.walk") { openMaps(mode: MKLaunchOptionsDirectionsModeWalking) }
            Button("Mit dem Auto", systemImage: "car") { openMaps(mode: MKLaunchOptionsDirectionsModeDriving) }
            Button("Mit Bus & Bahn", systemImage: "tram") { openMaps(mode: MKLaunchOptionsDirectionsModeTransit) }
        } label: {
            Label("Route", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                .font(.headline).frame(maxWidth: .infinity, minHeight: 42)
        }.buttonStyle(.bordered).buttonBorderShape(.roundedRectangle(radius: 18)).disabled(current.validLocation == nil)
    }

    private var information: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Über dieses Objekt").font(.headline)
            LabeledContent("Batterie", value: current.battery ?? "Unbekannt")
            LabeledContent("Netzwerk", value: current.provider.rjProviderName)
            if let date = current.reportDate { LabeledContent("Zuletzt gesehen", value: date.formatted(date: .abbreviated, time: .standard)) }
            if let accuracy = current.location?.accuracyM, accuracy > 0 { LabeledContent("Genauigkeit", value: "±\(accuracy.metersText)") }
            if let origin = model.locationService.location, let distance = current.distance(from: origin) { LabeledContent("Entfernung zu mir", value: distance.metersText) }
            if let note = current.details?.note, !note.isEmpty { Divider(); Text(note).font(.subheadline).textSelection(.enabled) }
        }.font(.subheadline).rjCard()
    }

    private var alarmSubtitle: String {
        let count = [current.foundNotification?.enabled, current.departureNotification?.enabled].filter { $0 == true }.count
        return count == 0 ? "Fund- und Bewegungsalarm einrichten" : "\(count) Alarm\(count == 1 ? "" : "e") aktiv"
    }

    private func detailRow(_ title: String, subtitle: String, icon: String, color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.title3).foregroundStyle(color).frame(width: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.body.weight(.medium)).foregroundStyle(.primary)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }.padding(.vertical, 12).contentShape(Rectangle())
    }

    private func openMaps(mode: String) {
        guard let location = current.validLocation else { return }
        let item = MKMapItem(placemark: MKPlacemark(coordinate: location.coordinate))
        item.name = current.name
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: mode])
    }

    private func recover() async {
        busy = true
        defer { busy = false }
        do { try await model.runAction("start_recovery", payload: ["tracker": current.ref, "confirmed": true]) }
        catch { model.errorMessage = error.localizedDescription }
    }
}

struct FusionSourcesCard: View {
    let tracker: Tracker
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Deine Ortungsnetze", systemImage: "point.3.connected.trianglepath.dotted").font(.headline)
            ForEach(tracker.fusionNetworkNames, id: \.self) { provider in
                let health = tracker.sourceHealth?.objectValue?[provider]?.objectValue
                HStack(spacing: 12) {
                    Image(systemName: provider.rjProviderSymbol).foregroundStyle(provider.rjProviderColor).frame(width: 26)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(provider.rjProviderName).font(.subheadline.weight(.semibold))
                            if provider == tracker.latestSourceName { Text("Letzte Quelle").font(.caption2).foregroundStyle(.blue) }
                        }
                        if let timestamp = health?["timestamp"]?.numberValue, timestamp > 0 {
                            FreshnessLabel(timestamp: Int(timestamp))
                        } else { Text("Keine Meldung verfügbar").font(.caption).foregroundStyle(.secondary) }
                    }
                    Spacer()
                    if let accuracy = health?["accuracy_m"]?.numberValue, accuracy > 0 {
                        Text("±\(accuracy.metersText)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
            }
            if let disagreement = tracker.networkDisagreement?.objectValue,
               let summary = disagreement["summary"]?.stringValue, !summary.isEmpty {
                Label(summary, systemImage: disagreement["status"]?.stringValue == "warning" ? "exclamationmark.triangle" : "checkmark.shield")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }.rjCard()
    }
}

struct TrackerEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let tracker: Tracker
    @State private var name: String
    @State private var emoji: String
    @State private var note: String
    @State private var busy = false
    @State private var error: String?
    init(tracker: Tracker) {
        self.tracker = tracker
        _name = State(initialValue: tracker.name)
        _emoji = State(initialValue: tracker.emoji ?? "📍")
        _note = State(initialValue: tracker.details?.note ?? "")
    }
    var body: some View {
        Form {
            Section("Objekt") {
                TextField("Name", text: $name)
                TextField("Symbol", text: $emoji)
                ScrollView(.horizontal) {
                    HStack {
                        ForEach(["🎒", "🔑", "🚲", "🧳", "🚗", "🛴", "👜", "📍"], id: \.self) { symbol in
                            Button { emoji = symbol } label: { Text(symbol).font(.title).padding(8) }.buttonStyle(.plain)
                        }
                    }
                }
            }
            Section("Notiz") { TextField("Zum Beispiel: im Innenfach", text: $note, axis: .vertical).lineLimit(3...6) }
            if let error { Section { Text(error).foregroundStyle(.red) } }
        }
        .navigationTitle("Objekt bearbeiten").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Sichern") { Task { await save() } }.disabled(busy || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name.count > 80 || note.count > 500 || emoji.count > 4)
            }
        }
        .interactiveDismissDisabled(busy)
    }
    private func save() async {
        busy = true; defer { busy = false }
        do {
            try await model.runAction("update_tracker_details", payload: ["tracker": tracker.ref, "name": name.trimmingCharacters(in: .whitespacesAndNewlines), "emoji": emoji, "note": note])
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

struct TrackerAutomationView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let tracker: Tracker
    @State private var radius = 150.0
    @State private var repeatAlarm = false
    @State private var retention = "30_days"
    @State private var busy = false
    @State private var error: String?
    private var current: Tracker { model.trackers.first { $0.ref == tracker.ref } ?? tracker }
    var body: some View {
        Form {
            Section {
                Toggle("Wenn gefunden", isOn: Binding(get: { current.foundNotification?.enabled == true }, set: { value in
                    perform("set_found_notification", ["enabled": value, "mode": repeatAlarm ? "always" : "once"])
                }))
                Toggle("Beim Wegbewegen", isOn: Binding(get: { current.departureNotification?.enabled == true }, set: { value in
                    perform("set_departure_notification", ["enabled": value, "radius_m": radius, "mode": repeatAlarm ? "always" : "once", "min_confirmations": 2])
                })).disabled(current.validLocation == nil)
            } header: { Text("Mitteilungen") } footer: {
                Text("Der Bewegungsalarm bezieht sich auf den Standort beim Einschalten. Der Server bestätigt das Verlassen anhand neuer Meldungen.")
            }
            Section("Beim nächsten Einschalten") {
                Toggle("Wiederholt benachrichtigen", isOn: $repeatAlarm)
                LabeledContent("Bewegungsradius", value: radius.metersText)
                Slider(value: $radius, in: 25...1000, step: 25)
            }
            Section {
                LabeledContent("Aufzeichnung", value: current.historyActive == true ? "Aktiv" : "Aus")
                Picker("Aufbewahren", selection: $retention) {
                    Text("7 Tage").tag("7_days"); Text("14 Tage").tag("14_days"); Text("30 Tage").tag("30_days"); Text("90 Tage").tag("90_days"); Text("Dauerhaft").tag("forever")
                }
                Button("Verlauf mit dieser Dauer aktivieren") { perform("set_history", ["enabled": true, "retention": retention]) }
                if current.historyActive == true {
                    Button("Aufzeichnung pausieren") { perform("set_history", ["enabled": false]) }
                }
            } header: { Text("Standortverlauf") } footer: {
                Text("Eine kürzere Aufbewahrung kann bei der nächsten Server-Bereinigung ältere Punkte entfernen. Beim Pausieren wird kein Verlauf aktiv gelöscht.")
            }
            if let error { Section { Text(error).foregroundStyle(.red) } }
        }
        .disabled(busy)
        .navigationTitle("Mitteilungen & Verlauf").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() }.disabled(busy) } }
        .overlay { if busy { ProgressView().padding(20).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18)) } }
        .interactiveDismissDisabled(busy)
    }
    private func perform(_ action: String, _ payload: [String: Any]) {
        guard !busy else { return }
        busy = true; error = nil
        Task {
            defer { busy = false }
            do { try await model.runAction(action, payload: payload.merging(["tracker": tracker.ref]) { _, new in new }) }
            catch { self.error = error.localizedDescription }
        }
    }
}
