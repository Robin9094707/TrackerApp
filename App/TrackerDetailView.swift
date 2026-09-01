import SwiftUI
import MapKit

struct TrackerDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let tracker: Tracker

    private enum DetailDetent: Int { case compact, medium, large }

    @State private var showRecoveryConfirm = false
    @State private var mapPosition: MapCameraPosition = .automatic
    @State private var detent: DetailDetent = .medium
    @GestureState private var dragTranslation: CGFloat = 0

    private var current: Tracker { model.trackers.first(where: { $0.ref == tracker.ref }) ?? tracker }

    private var panelCoverage: CGFloat {
        switch detent {
        case .compact: 0.34
        case .medium: 0.58
        case .large: 0.88
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                heroMap
                    .ignoresSafeArea()

                detailSheet(maxHeight: geometry.size.height)
                    .frame(height: max(235, detailHeight(maxHeight: geometry.size.height) - dragTranslation))
                    .padding(.horizontal, 7)
                    .padding(.bottom, 3)
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .task { focusCurrent(animated: false) }
        .onChange(of: current.location) { _, _ in focusCurrent() }
        .onChange(of: detent) { _, _ in focusCurrent() }
    }

    private var heroMap: some View {
        Map(position: $mapPosition) {
            if let location = current.location {
                if let accuracy = location.accuracyM, accuracy > 0 {
                    MapCircle(center: location.coordinate, radius: max(accuracy, 3))
                        .foregroundStyle(Color.blue.opacity(0.14))
                        .stroke(Color.blue.opacity(0.58), lineWidth: 1.5)
                }
                Annotation(current.name, coordinate: location.coordinate, anchor: .bottom) {
                    TrackerMapBubble(tracker: current, selected: true, locating: model.isLocating(current))
                }
            }
        }
        .mapStyle(.standard(
            elevation: .realistic,
            pointsOfInterest: .including([.publicTransport, .park, .hospital, .school])
        ))
        .mapControls {
            MapCompass()
            MapPitchToggle()
            MapUserLocationButton()
        }
        .overlay(alignment: .topTrailing) {
            VStack(spacing: 10) {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.title3.weight(.semibold))
                        .rjGlassControl()
                }
                .buttonStyle(.plain)

                Button { focusCurrent() } label: {
                    Image(systemName: "scope")
                        .rjGlassControl()
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 56)
            .padding(.trailing, 14)
        }
    }

    private func detailSheet(maxHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(.secondary.opacity(0.48))
                .frame(width: 42, height: 5)
                .padding(.top, 9)
                .padding(.bottom, 10)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .onTapGesture { cycleDetent() }
                .gesture(
                    DragGesture(minimumDistance: 5)
                        .updating($dragTranslation) { value, state, _ in state = value.translation.height }
                        .onEnded { value in settleDetent(value.translation.height, predicted: value.predictedEndTranslation.height) }
                )

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    actionGrid
                    accuracyCard
                    if current.provider == "fusion" { fusionDetails }
                    notificationCard
                    trackerInfo
                    if ["apple", "fusion"].contains(current.provider) { recoveryCard }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.visible)
        }
        .rjGlass(in: RoundedRectangle(cornerRadius: RJDesign.sheetCorner, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 28, y: 12)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 13) {
            ZStack {
                Circle().fill(.secondary.opacity(0.10))
                Text(current.emoji ?? "📍")
                    .font(.system(size: 31))
            }
            .frame(width: 60, height: 60)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(current.name)
                        .font(.largeTitle.bold())
                        .lineLimit(2)
                        .minimumScaleFactor(0.72)
                    Spacer(minLength: 8)
                    ProviderBadge(provider: current.provider)
                }

                ResolvedAddressText(
                    location: current.location,
                    fallback: current.location == nil ? "Noch kein Standort verfügbar" : "Adresse wird ermittelt …"
                )
                .font(.title3)
                .lineLimit(3)

                HStack(spacing: 7) {
                    FreshnessLabel(timestamp: current.location?.timestamp ?? current.lastSeenTs)
                    if let battery = current.battery, !battery.isEmpty {
                        Text("•").foregroundStyle(.secondary)
                        Label(battery, systemImage: "battery.50percent")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if current.provider == "fusion", let source = current.latestSourceName {
                        Text("•").foregroundStyle(.secondary)
                        Text(source.rjProviderName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(source.rjProviderColor)
                    }
                }
            }
        }
    }

    private var actionGrid: some View {
        HStack(spacing: 10) {
            DetailActionTile(
                title: model.isLocating(current) ? "Ortung läuft …" : "Orten",
                subtitle: model.isLocating(current) ? "Neuer Standort wird gesucht" : "Standort aktualisieren",
                symbol: "location.fill",
                tint: .green,
                loading: model.isLocating(current)
            ) {
                Task { await model.locate(current) }
            }
            .disabled(model.isLocating(current))

            DetailActionTile(
                title: "Route",
                subtitle: current.location == nil ? "Nicht verfügbar" : "Apple Karten öffnen",
                symbol: "arrow.triangle.turn.up.right.diamond.fill",
                tint: .cyan
            ) {
                if let location = current.location { openMaps(location) }
            }
            .disabled(current.location == nil)

            NavigationLink { HistoryView(tracker: current) } label: {
                VStack(alignment: .leading, spacing: 8) {
                    ZStack {
                        Circle().fill(Color.blue.opacity(0.16)).frame(width: 42, height: 42)
                        Image(systemName: "clock.arrow.circlepath").font(.title3).foregroundStyle(.blue)
                    }
                    Text("Verlauf").font(.headline).foregroundStyle(.primary)
                    Text("Zeitleiste anzeigen").font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 116, alignment: .leading)
                .padding(14)
                .rjGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private var accuracyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Standortgenauigkeit", systemImage: "scope")
                    .font(.headline)
                Spacer()
                AccuracyPill(accuracy: current.location?.accuracyM)
            }
            Text("Der blaue Kreis auf der Karte zeigt den vom Netzwerk gemeldeten Genauigkeitsbereich der letzten Ortung.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let confidence = current.location?.confidence {
                LabeledContent("Vertrauen", value: "\(Int((confidence <= 1 ? confidence * 100 : confidence).rounded())) %")
            }
            if let quality = current.location?.quality, !quality.isEmpty {
                LabeledContent("Qualität", value: quality.capitalized)
            }
        }
        .padding(16)
        .background(.blue.opacity(0.04), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .rjGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var fusionDetails: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Fusion", systemImage: "point.3.connected.trianglepath.dotted")
                    .font(.headline)
                Spacer()
                if let source = current.latestSourceName { SourceBadge(source: source) }
            }

            if let source = current.latestSourceName {
                LabeledContent("Letzte Quelle", value: source.rjProviderName)
            } else {
                LabeledContent("Letzte Quelle", value: "Nicht gemeldet")
            }

            if !current.fusionNetworkNames.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Verknüpfte Netze")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        ForEach(current.fusionNetworkNames, id: \.self) { SourceBadge(source: $0) }
                    }
                }
            }

            if let sourceHealth = current.sourceHealth?.objectValue, !sourceHealth.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Provider-Status")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(sourceHealth.keys.sorted(), id: \.self) { key in
                        HStack {
                            SourceBadge(source: key)
                            Spacer()
                            Text("Daten vorhanden")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(.purple.opacity(0.04), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .rjGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var notificationCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label("Mitteilung an mich", systemImage: "bell.fill")
                .font(.headline)
                .foregroundStyle(.purple)
                .padding(.bottom, 12)
            Divider()
            Toggle(isOn: Binding(
                get: { current.foundNotification?.enabled == true },
                set: { enabled in Task { await model.setFoundNotification(current, enabled: enabled) } }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Wenn gefunden")
                    Text("Bei einer neuen Ortung benachrichtigen")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(model.isUpdatingNotification(current))
            .padding(.vertical, 12)
        }
        .rjCompactCard()
    }

    private var trackerInfo: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Details", systemImage: "info.circle.fill").font(.headline)
            LabeledContent("Netzwerk", value: current.provider.rjProviderName)
            LabeledContent("Batterie", value: current.battery ?? "Unbekannt")
            LabeledContent("Verlauf", value: current.historyActive == true ? "Aktiv" : "Aus")
            if let location = current.location, let accuracy = location.accuracyM, accuracy > 0 {
                LabeledContent("Genauigkeit", value: "±\(accuracy.metersText)")
            }
            if let networks = current.linkedNetworks, !networks.isEmpty {
                LabeledContent("Fusion-Netze", value: networks.map(\.rjProviderName).joined(separator: " + "))
            }
        }
        .rjCompactCard()
    }

    private var recoveryCard: some View {
        Button(role: .destructive) { showRecoveryConfirm = true } label: {
            Label("Recovery Guard aktivieren", systemImage: "lifepreserver.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .rjGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .confirmationDialog("Recovery Guard starten?", isPresented: $showRecoveryConfirm, titleVisibility: .visible) {
            Button("Aktivieren", role: .destructive) { Task { await startRecovery() } }
            Button("Abbrechen", role: .cancel) { }
        } message: {
            Text("Der Server beginnt einen Recovery-Fall für diesen Tracker. Das ist kein offizieller Apple-Lost-Mode.")
        }
    }

    private func detailHeight(maxHeight: CGFloat) -> CGFloat {
        switch detent {
        case .compact: return min(maxHeight * 0.34, 310)
        case .medium: return min(maxHeight * 0.58, 535)
        case .large: return min(maxHeight * 0.88, 790)
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

    private func settleDetent(_ translation: CGFloat, predicted: CGFloat) {
        let intent = translation + (predicted - translation) * 0.2
        withAnimation(.snappy(duration: 0.32)) {
            if intent < -70 {
                if detent == .compact { detent = .medium } else { detent = .large }
            } else if intent > 70 {
                if detent == .large { detent = .medium } else { detent = .compact }
            }
        }
    }

    private func focusCurrent(animated: Bool = true) {
        guard let location = current.location else { return }
        let region = RJMapCamera.focusedRegion(for: location, panelCoverage: panelCoverage)
        if animated {
            withAnimation(.snappy(duration: 0.42)) { mapPosition = .region(region) }
        } else {
            mapPosition = .region(region)
        }
    }

    private func startRecovery() async {
        do {
            _ = try await APIClient.shared.action("start_recovery", payload: ["tracker": current.ref, "confirmed": true])
            await model.refresh()
            Haptics.success()
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func openMaps(_ location: TrackerLocation) {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: location.coordinate))
        item.name = current.name
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
    }
}

private struct DetailActionTile: View {
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
                    Circle().fill(tint.opacity(0.17)).frame(width: 42, height: 42)
                    if loading { ProgressView().controlSize(.small) }
                    else { Image(systemName: symbol).font(.title3).foregroundStyle(tint) }
                }
                Text(title).font(.headline).foregroundStyle(.primary).lineLimit(1)
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            .frame(maxWidth: .infinity, minHeight: 116, alignment: .leading)
            .padding(14)
            .rjGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
