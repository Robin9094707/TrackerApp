import SwiftUI
import MapKit

struct TrackerMapView: View {
    @Environment(AppModel.self) private var model
    @State private var selected: Tracker?
    @State private var position: MapCameraPosition = .automatic

    private var located: [Tracker] { model.filteredTrackers.filter { $0.location != nil } }
    private var current: Tracker? {
        guard let selected else { return nil }
        return model.trackers.first(where: { $0.ref == selected.ref }) ?? selected
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Map(position: $position) {
                ForEach(located) { tracker in
                    if let location = tracker.location {
                        if current?.ref == tracker.ref, let accuracy = location.accuracyM, accuracy > 0 {
                            MapCircle(center: location.coordinate, radius: max(accuracy, 3))
                                .foregroundStyle(Color.blue.opacity(0.14))
                                .stroke(Color.blue.opacity(0.58), lineWidth: 1.5)
                        }

                        Annotation(tracker.name, coordinate: location.coordinate, anchor: .bottom) {
                            Button { select(tracker) } label: {
                                TrackerMapBubble(
                                    tracker: tracker,
                                    selected: current?.ref == tracker.ref,
                                    locating: model.isLocating(tracker)
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(tracker.name), \(tracker.provider.rjProviderName)")
                        }
                    }
                }

                ForEach(model.bootstrap?.geofences ?? []) { fence in
                    MapCircle(center: fence.center.coordinate, radius: fence.radiusM ?? 100)
                        .foregroundStyle(.tint.opacity(0.07))
                        .stroke(.tint.opacity(0.35), lineWidth: 1)
                }
            }
            .mapStyle(.standard(
                elevation: .realistic,
                pointsOfInterest: .including([.publicTransport, .school, .park, .hospital])
            ))
            .mapControls {
                MapCompass()
                MapPitchToggle()
                MapScaleView()
                MapUserLocationButton()
            }
            .ignoresSafeArea(edges: .bottom)

            if let current {
                selectedCard(current)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .navigationTitle("Karte")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationDestination(for: Tracker.self) { TrackerDetailView(tracker: $0) }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    withAnimation(.snappy(duration: 0.35)) {
                        selected = nil
                        position = .automatic
                    }
                } label: {
                    Image(systemName: "map.fill")
                        .rjGlassControl()
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Alle Tracker zeigen")
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button { Task { await model.locateAll() } } label: {
                    Group {
                        if !model.locatingRefs.isEmpty { ProgressView().controlSize(.small) }
                        else { Image(systemName: "location.fill") }
                    }
                    .rjGlassControl()
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Alle Tracker orten")
            }
        }
        .onChange(of: current?.location) { _, _ in
            if let current { focus(current) }
        }
    }

    private func selectedCard(_ tracker: Tracker) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle().fill(.secondary.opacity(0.10))
                    Text(tracker.emoji ?? "📍")
                        .font(.title2)
                }
                .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 3) {
                    Text(tracker.name)
                        .font(.title3.bold())
                        .lineLimit(1)
                    ResolvedAddressText(location: tracker.location, fallback: "Adresse wird ermittelt …")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    HStack(spacing: 7) {
                        FreshnessLabel(timestamp: tracker.location?.timestamp ?? tracker.lastSeenTs)
                        if tracker.provider == "fusion", let source = tracker.latestSourceName {
                            Text("•").foregroundStyle(.secondary)
                            Text(source.rjProviderName)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(source.rjProviderColor)
                        }
                    }
                }

                Spacer(minLength: 6)
                AccuracyPill(accuracy: tracker.location?.accuracyM)
            }

            HStack(spacing: 10) {
                Button { Task { await model.locate(tracker) } } label: {
                    Group {
                        if model.isLocating(tracker) {
                            HStack(spacing: 7) {
                                ProgressView().controlSize(.small)
                                Text("Ortung läuft …")
                            }
                        } else {
                            Label("Orten", systemImage: "location.fill")
                        }
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .rjGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(model.isLocating(tracker))

                NavigationLink(value: tracker) {
                    Label("Details", systemImage: "info.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .rjGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .rjGlass(in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .shadow(color: .black.opacity(0.17), radius: 24, y: 10)
    }

    private func select(_ tracker: Tracker) {
        withAnimation(.snappy(duration: 0.30)) { selected = tracker }
        Haptics.impact()
        focus(tracker)
    }

    private func focus(_ tracker: Tracker) {
        guard let location = tracker.location else { return }
        let region = RJMapCamera.focusedRegion(for: location, panelCoverage: 0.27)
        withAnimation(.snappy(duration: 0.42)) {
            position = .region(region)
        }
    }
}
