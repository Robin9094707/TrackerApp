import SwiftUI
import MapKit

struct TrackerHomeView: View {
    @Environment(AppModel.self) private var model

    private enum SheetDetent: Int, CaseIterable {
        case compact, medium, large
    }

    @State private var provider = "all"
    @State private var selected: Tracker?
    @State private var position: MapCameraPosition = .automatic
    @State private var detent: SheetDetent = .medium
    @State private var showingTrackerDetail = false
    @GestureState private var dragTranslation: CGFloat = 0

    private var located: [Tracker] { model.filteredTrackers.filter { $0.location != nil } }
    private var current: Tracker? {
        guard let selected else { return nil }
        return model.trackers.first(where: { $0.ref == selected.ref }) ?? selected
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                trackerMap
                    .ignoresSafeArea(edges: .bottom)

                trackerPanel(maxHeight: geometry.size.height)
                    .frame(height: max(210, panelHeight(maxHeight: geometry.size.height) - dragTranslation))
                    .padding(.horizontal, 8)
                    .padding(.bottom, 3)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationDestination(for: Tracker.self) { TrackerDetailView(tracker: $0) }
        .task {
            if selected == nil { selected = model.filteredTrackers.first }
        }
        .onChange(of: model.filteredTrackers) { _, trackers in
            if let selected, !trackers.contains(where: { $0.ref == selected.ref }) {
                self.selected = trackers.first
                showingTrackerDetail = false
            }
        }
        .toolbar { mapToolbar }
    }

    private var trackerMap: some View {
        Map(position: $position) {
            ForEach(located) { tracker in
                if let location = tracker.location {
                    if current?.ref == tracker.ref, let accuracy = location.accuracyM, accuracy > 0 {
                        MapCircle(center: location.coordinate, radius: max(accuracy, 3))
                            .foregroundStyle(Color.blue.opacity(0.16))
                            .stroke(Color.blue.opacity(0.55), lineWidth: 1.4)
                    }

                    Annotation(tracker.name, coordinate: location.coordinate, anchor: .bottom) {
                        Button {
                            select(tracker, showDetails: true)
                        } label: {
                            TrackerMapBubble(
                                tracker: tracker,
                                selected: current?.ref == tracker.ref,
                                locating: model.isLocating(tracker)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .including([.publicTransport, .school, .park, .hospital])))
        .mapControls {
            MapCompass()
            MapPitchToggle()
            MapUserLocationButton()
        }
    }

    @ToolbarContentBuilder
    private var mapToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button { position = .automatic } label: {
                Image(systemName: "map.fill")
                    .frame(width: 36, height: 36)
                    .rjGlass(in: Circle())
            }
            .accessibilityLabel("Alle Tracker zeigen")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button { Task { await model.locateAll() } } label: {
                Group {
                    if !model.locatingRefs.isEmpty {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "location.fill")
                    }
                }
                .frame(width: 36, height: 36)
            }
            .rjGlass(in: Circle())
            .accessibilityLabel("Alle Tracker orten")
        }
    }

    private func trackerPanel(maxHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            sheetHandle(maxHeight: maxHeight)

            if showingTrackerDetail, let current {
                selectedTrackerPanel(current)
            } else {
                trackerListPanel
            }
        }
        .frame(maxWidth: .infinity)
        .rjGlass(in: RoundedRectangle(cornerRadius: RJDesign.sheetCorner, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 26, y: 11)
        .animation(.snappy(duration: 0.32), value: detent)
        .animation(.snappy(duration: 0.28), value: showingTrackerDetail)
    }

    private func sheetHandle(maxHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(.secondary.opacity(0.5))
                .frame(width: 42, height: 5)
                .padding(.top, 9)
                .padding(.bottom, 10)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { cycleDetent() }
        .gesture(
            DragGesture(minimumDistance: 5)
                .updating($dragTranslation) { value, state, _ in
                    state = value.translation.height
                }
                .onEnded { value in
                    settleDetent(translation: value.translation.height, velocity: value.predictedEndTranslation.height - value.translation.height)
                }
        )
        .accessibilityLabel("Panel hoch- oder runterziehen")
    }

    private var trackerListPanel: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Objekte")
                        .font(.largeTitle.bold())
                    Text("\(model.filteredTrackers.count) Tracker")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button { Task { await model.refresh() } } label: {
                    Group {
                        if model.isRefreshing { ProgressView().controlSize(.small) }
                        else { Image(systemName: "arrow.clockwise") }
                    }
                    .frame(width: 44, height: 44)
                    .background(.secondary.opacity(0.1), in: Circle())
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 10)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Tracker suchen", text: Binding(get: { model.searchText }, set: { model.searchText = $0 }))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if !model.searchText.isEmpty {
                    Button { model.searchText = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                }
            }
            .padding(.horizontal, 13)
            .frame(height: 42)
            .background(.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.horizontal, 16)
            .padding(.bottom, 10)

            Picker("Netz", selection: $provider) {
                Text("Alle").tag("all")
                Text("Fusion").tag("fusion")
                Text("Apple").tag("apple")
                Text("Google").tag("google")
                Text("Samsung").tag("samsung")
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .onChange(of: provider) { _, newValue in model.providerFilter = newValue }

            ScrollView {
                LazyVStack(spacing: 0) {
                    if model.filteredTrackers.isEmpty {
                        ContentUnavailableView("Keine Tracker", systemImage: "location.slash")
                            .padding(.vertical, 30)
                    }

                    ForEach(model.filteredTrackers) { tracker in
                        Button { select(tracker, showDetails: true) } label: {
                            FindMyTrackerRow(
                                tracker: tracker,
                                selected: current?.ref == tracker.ref,
                                locating: model.isLocating(tracker)
                            )
                        }
                        .buttonStyle(.plain)

                        if tracker.id != model.filteredTrackers.last?.id {
                            Divider().padding(.leading, 78)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
            .scrollIndicators(.visible)
        }
    }

    private func selectedTrackerPanel(_ tracker: Tracker) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(tracker.name)
                            .font(.largeTitle.bold())
                            .lineLimit(2)
                            .minimumScaleFactor(0.78)
                        ResolvedAddressText(location: tracker.location, fallback: "Adresse wird ermittelt …")
                            .font(.title3)
                            .lineLimit(2)
                        HStack(spacing: 7) {
                            FreshnessLabel(timestamp: tracker.location?.timestamp ?? tracker.lastSeenTs)
                            if let battery = tracker.battery, !battery.isEmpty {
                                Text("•").foregroundStyle(.secondary)
                                Label(battery, systemImage: "battery.50percent")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    Spacer(minLength: 6)
                    Button {
                        withAnimation(.snappy(duration: 0.28)) { showingTrackerDetail = false; detent = .medium }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.title3.weight(.semibold))
                            .frame(width: 44, height: 44)
                            .background(.secondary.opacity(0.12), in: Circle())
                    }
                    .buttonStyle(.plain)
                }

                quickActions(tracker)

                if tracker.provider == "fusion" {
                    fusionCard(tracker)
                }

                notificationCard(tracker)

                NavigationLink(value: tracker) {
                    Label("Alle Details & Verlauf", systemImage: "info.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.visible)
    }

    private func quickActions(_ tracker: Tracker) -> some View {
        HStack(spacing: 12) {
            QuickActionTile(
                title: model.isLocating(tracker) ? "Ortung läuft …" : "Orten",
                subtitle: model.isLocating(tracker) ? "Suche nach neuem Standort" : "Standort aktualisieren",
                symbol: "location.fill",
                tint: .green,
                loading: model.isLocating(tracker)
            ) {
                Task { await model.locate(tracker) }
            }
            .disabled(model.isLocating(tracker))

            QuickActionTile(
                title: "Route",
                subtitle: tracker.location == nil ? "Kein Standort" : "In Apple Karten",
                symbol: "arrow.triangle.turn.up.right.diamond.fill",
                tint: .cyan
            ) {
                if let location = tracker.location { openMaps(tracker, location) }
            }
            .disabled(tracker.location == nil)
        }
    }

    private func notificationCard(_ tracker: Tracker) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Label("Mitteilung an mich", systemImage: "bell.fill")
                .font(.headline)
                .foregroundStyle(.purple)
                .padding(.bottom, 12)

            Divider()

            Toggle(isOn: Binding(
                get: { tracker.foundNotification?.enabled == true },
                set: { enabled in Task { await model.setFoundNotification(tracker, enabled: enabled) } }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Wenn gefunden")
                        .foregroundStyle(.primary)
                    Text("Benachrichtigt dich bei einer neuen Ortung")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(model.isUpdatingNotification(tracker))
            .padding(.vertical, 12)
        }
        .padding(16)
        .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func fusionCard(_ tracker: Tracker) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Fusion-Details", systemImage: "point.3.connected.trianglepath.dotted")
                    .font(.headline)
                Spacer()
                if let source = tracker.latestSourceName { SourceBadge(source: source) }
            }

            if let source = tracker.latestSourceName {
                LabeledContent("Letzte Ortung", value: source.rjProviderName)
            } else {
                LabeledContent("Letzte Ortung", value: "Quelle nicht gemeldet")
            }

            if !tracker.fusionNetworkNames.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Verknüpfte Netze").font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        ForEach(tracker.fusionNetworkNames, id: \.self) { SourceBadge(source: $0) }
                    }
                }
            }

            if let confidence = tracker.location?.confidence {
                LabeledContent("Fusion-Vertrauen", value: "\(Int((confidence <= 1 ? confidence * 100 : confidence).rounded())) %")
            }
            if let quality = tracker.location?.quality, !quality.isEmpty {
                LabeledContent("Standortqualität", value: quality.capitalized)
            }
            if let accuracy = tracker.location?.accuracyM, accuracy > 0 {
                LabeledContent("Genauigkeit", value: "±\(accuracy.metersText)")
            }
        }
        .padding(16)
        .background(.purple.opacity(0.08), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func panelHeight(maxHeight: CGFloat) -> CGFloat {
        switch detent {
        case .compact: return min(maxHeight * 0.34, 300)
        case .medium: return min(maxHeight * 0.58, 520)
        case .large: return min(maxHeight * 0.86, 780)
        }
    }

    private func cycleDetent() {
        withAnimation(.snappy(duration: 0.32)) {
            switch detent {
            case .compact: detent = .medium
            case .medium: detent = .large
            case .large: detent = .compact
            }
        }
    }

    private func settleDetent(translation: CGFloat, velocity: CGFloat) {
        let intent = translation + velocity * 0.2
        withAnimation(.snappy(duration: 0.32)) {
            if intent < -70 {
                if detent == .compact { detent = .medium }
                else { detent = .large }
            } else if intent > 70 {
                if detent == .large { detent = .medium }
                else { detent = .compact }
            }
        }
    }

    private func select(_ tracker: Tracker, showDetails: Bool) {
        selected = tracker
        showingTrackerDetail = showDetails
        if showDetails { detent = .medium }
        Haptics.impact()
        guard let location = tracker.location else { return }
        let accuracy = max(location.accuracyM ?? 80, 70)
        withAnimation(.snappy(duration: 0.45)) {
            position = .region(MKCoordinateRegion(
                center: location.coordinate,
                latitudinalMeters: max(650, accuracy * 6),
                longitudinalMeters: max(650, accuracy * 6)
            ))
        }
    }

    private func openMaps(_ tracker: Tracker, _ location: TrackerLocation) {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: location.coordinate))
        item.name = tracker.name
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
    }
}

private struct FindMyTrackerRow: View {
    let tracker: Tracker
    let selected: Bool
    let locating: Bool

    private var timestamp: Int? { tracker.location?.timestamp ?? tracker.lastSeenTs }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(selected ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.12))
                Text(tracker.emoji ?? "📍").font(.title2)
            }
            .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text(tracker.name).font(.headline).lineLimit(1)
                    if tracker.provider == "fusion" {
                        Image(systemName: "sparkles").font(.caption).foregroundStyle(.purple)
                    }
                }

                ResolvedAddressText(location: tracker.location, fallback: tracker.location == nil ? "Noch kein Standort" : "Adresse wird ermittelt …")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                HStack(spacing: 7) {
                    FreshnessLabel(timestamp: timestamp)
                    if tracker.provider == "fusion", let source = tracker.latestSourceName {
                        Text("•").font(.caption).foregroundStyle(.secondary)
                        Text(source.rjProviderName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(source.rjProviderColor)
                    }
                }
            }

            Spacer(minLength: 8)

            if locating {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

private struct QuickActionTile: View {
    let title: String
    let subtitle: String
    let symbol: String
    let tint: Color
    var loading = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack {
                    Circle().fill(tint.opacity(0.18)).frame(width: 42, height: 42)
                    if loading { ProgressView().controlSize(.small) }
                    else { Image(systemName: symbol).font(.title3).foregroundStyle(tint) }
                }
                Text(title).font(.headline).foregroundStyle(.primary).lineLimit(1)
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            .frame(maxWidth: .infinity, minHeight: 116, alignment: .leading)
            .padding(14)
            .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
