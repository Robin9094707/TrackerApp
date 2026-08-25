import SwiftUI
import MapKit

struct TrackerHomeView: View {
    @Environment(AppModel.self) private var model
    @State private var provider = "all"
    @State private var selected: Tracker?
    @State private var position: MapCameraPosition = .automatic
    @State private var panelExpanded = false

    private var located: [Tracker] { model.filteredTrackers.filter { $0.location != nil } }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                trackerMap
                    .ignoresSafeArea(edges: .bottom)

                trackerPanel(maxHeight: geometry.size.height)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 4)
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
            }
        }
        .toolbar {
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
                    if !model.locatingRefs.isEmpty {
                        ProgressView().controlSize(.small).frame(width: 36, height: 36)
                    } else {
                        Image(systemName: "location.fill").frame(width: 36, height: 36)
                    }
                }
                .rjGlass(in: Circle())
                .accessibilityLabel("Alle Tracker orten")
            }
        }
    }

    private var trackerMap: some View {
        Map(position: $position) {
            ForEach(located) { tracker in
                if let location = tracker.location {
                    if selected?.ref == tracker.ref, let accuracy = location.accuracyM, accuracy > 0 {
                        MapCircle(center: location.coordinate, radius: max(accuracy, 3))
                            .foregroundStyle(Color.accentColor.opacity(0.13))
                            .stroke(Color.accentColor.opacity(0.55), lineWidth: 1.5)
                    }

                    Annotation(tracker.name, coordinate: location.coordinate, anchor: .center) {
                        TrackerMapMarker(
                            tracker: tracker,
                            selected: selected?.ref == tracker.ref,
                            locating: model.isLocating(tracker)
                        ) {
                            select(tracker)
                        }
                    }
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll))
        .mapControls {
            MapCompass()
            MapScaleView()
            MapUserLocationButton()
        }
    }

    private func trackerPanel(maxHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.snappy(duration: 0.35)) { panelExpanded.toggle() }
            } label: {
                Capsule()
                    .fill(.secondary.opacity(0.45))
                    .frame(width: 42, height: 5)
                    .padding(.top, 9)
                    .padding(.bottom, 10)
            }
            .buttonStyle(.plain)

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tracker").font(.largeTitle.bold())
                    Text("\(model.filteredTrackers.count) Geräte & Tags")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button { Task { await model.refresh() } } label: {
                    if model.isRefreshing { ProgressView().controlSize(.small) }
                    else { Image(systemName: "arrow.clockwise") }
                }
                .frame(width: 44, height: 44)
                .background(.secondary.opacity(0.1), in: Circle())
            }
            .padding(.horizontal, 18)
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
            .padding(.bottom, 10)
            .onChange(of: provider) { _, newValue in
                model.providerFilter = newValue
            }

            ScrollView {
                LazyVStack(spacing: 0) {
                    if model.filteredTrackers.isEmpty {
                        ContentUnavailableView("Keine Tracker", systemImage: "location.slash")
                            .padding(.vertical, 30)
                    }

                    ForEach(model.filteredTrackers) { tracker in
                        Button {
                            select(tracker)
                        } label: {
                            FindMyTrackerRow(
                                tracker: tracker,
                                selected: selected?.ref == tracker.ref,
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
            }

            if let current = selected.flatMap({ selected in model.trackers.first(where: { $0.ref == selected.ref }) ?? selected }) {
                Divider()
                HStack(spacing: 12) {
                    Button {
                        Task { await model.locate(current) }
                    } label: {
                        Group {
                            if model.isLocating(current) {
                                HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Ortung läuft …") }
                            } else {
                                Label("Jetzt orten", systemImage: "location.fill")
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isLocating(current))

                    NavigationLink(value: current) {
                        Image(systemName: "info.circle.fill")
                            .font(.title3)
                            .frame(width: 48, height: 42)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(14)
            }
        }
        .frame(height: panelExpanded ? min(maxHeight * 0.72, 650) : min(maxHeight * 0.42, 370))
        .rjGlass(in: RoundedRectangle(cornerRadius: 34, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 24, y: 10)
        .animation(.snappy(duration: 0.35), value: panelExpanded)
    }

    private func select(_ tracker: Tracker) {
        selected = tracker
        Haptics.impact()
        if let location = tracker.location {
            let accuracy = max(location.accuracyM ?? 80, 80)
            withAnimation(.snappy(duration: 0.45)) {
                position = .region(MKCoordinateRegion(
                    center: location.coordinate,
                    latitudinalMeters: max(700, accuracy * 6),
                    longitudinalMeters: max(700, accuracy * 6)
                ))
            }
        }
    }
}

private struct TrackerMapMarker: View {
    let tracker: Tracker
    let selected: Bool
    let locating: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if selected {
                    Circle()
                        .fill(Color.accentColor.opacity(0.16))
                        .frame(width: 62, height: 62)
                }
                Circle()
                    .fill(.background)
                    .frame(width: selected ? 48 : 42, height: selected ? 48 : 42)
                    .shadow(color: .black.opacity(0.18), radius: 6, y: 3)

                if locating {
                    ProgressView().controlSize(.small)
                } else {
                    Text(tracker.emoji ?? "📍")
                        .font(selected ? .title2 : .title3)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

private struct FindMyTrackerRow: View {
    let tracker: Tracker
    let selected: Bool
    let locating: Bool

    private var timestamp: Int? { tracker.location?.timestamp ?? tracker.lastSeenTs }
    private var subtitle: String {
        if let address = tracker.location?.address?.bestText, !address.isEmpty { return address }
        if let accuracy = tracker.location?.accuracyM, accuracy > 0 { return "Genauigkeit ±\(accuracy.metersText)" }
        return tracker.location == nil ? "Noch kein Standort" : tracker.provider.capitalized
    }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(selected ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.1))
                Text(tracker.emoji ?? "📍").font(.title2)
            }
            .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(tracker.name).font(.headline).lineLimit(1)
                    if tracker.provider == "fusion" {
                        Image(systemName: "sparkles").font(.caption).foregroundStyle(.tint)
                    }
                }
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(spacing: 7) {
                    ProviderBadge(provider: tracker.provider)
                    AccuracyPill(accuracy: tracker.location?.accuracyM)
                }
            }

            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 8) {
                if locating {
                    ProgressView().controlSize(.small)
                    Text("Orte …").font(.caption2).foregroundStyle(.secondary)
                } else {
                    FreshnessLabel(timestamp: timestamp)
                    Image(systemName: selected ? "checkmark.circle.fill" : "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}
