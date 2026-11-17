import SwiftUI
import SpotIntegration

// MARK: - 8.2 Liquid Glass toolkit
//
// Every iOS 26 Liquid Glass API the app uses goes through these wrappers, so the
// same views still run on iOS 18 with a material fallback. Patterns follow
// Apple's Liquid Glass guidance: glass for the control layer, GlassEffectContainer
// around neighbouring glass, glassEffectID for morphing, interactive glass for
// tappable surfaces and tinted glass only for the one prominent action.

enum RJRuntime {
    /// UI tests tap tab bar buttons directly, so the tab bar must not minimize there.
    static let isUITesting = ProcessInfo.processInfo.arguments.contains { $0.hasPrefix("--ui-testing") }
}

extension View {
    /// Liquid Glass surface in any shape. Falls back to a material with a light rim.
    @ViewBuilder
    func rjGlassSurface<S: Shape>(_ shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular.tint(tint).interactive(interactive), in: shape)
        } else {
            self.modifier(RJLegacyGlass(shape: shape, tint: tint))
        }
    }

    /// `.glass` / `.glassProminent` button styles with bordered fallbacks.
    @ViewBuilder
    func rjGlassButtonStyle(prominent: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            if prominent { self.buttonStyle(.glassProminent) } else { self.buttonStyle(.glass) }
        } else {
            if prominent { self.rjGlassButtonStyle(prominent: true) } else { self.rjGlassButtonStyle() }
        }
    }

    /// Prominent tinted glass for a single toolbar action; system style before iOS 26.
    @ViewBuilder
    func rjToolbarProminent() -> some View {
        if #available(iOS 26.0, *) { self.buttonStyle(.glassProminent) } else { self }
    }

    /// Stable identity so glass shapes morph into each other inside a container.
    @ViewBuilder
    func rjGlassID(_ id: String, in namespace: Namespace.ID) -> some View {
        if #available(iOS 26.0, *) { self.glassEffectID(id, in: namespace) } else { self }
    }

    /// Merges several glass shapes with the same id into one surface.
    @ViewBuilder
    func rjGlassUnion(_ id: String, in namespace: Namespace.ID) -> some View {
        if #available(iOS 26.0, *) { self.glassEffectUnion(id: id, namespace: namespace) } else { self }
    }

    /// Glass that materializes instead of sliding when it is inserted.
    @ViewBuilder
    func rjGlassMaterialize() -> some View {
        if #available(iOS 26.0, *) { self.glassEffectTransition(.materialize) } else { self }
    }

    /// Soft scroll edge under the floating glass bars.
    @ViewBuilder
    func rjSoftScrollEdge() -> some View {
        if #available(iOS 26.0, *) { self.scrollEdgeEffectStyle(.soft, for: .all) } else { self }
    }

    /// Mirrors the content into the safe area behind the floating bars.
    @ViewBuilder
    func rjBackgroundExtension() -> some View {
        if #available(iOS 26.0, *) { self.backgroundExtensionEffect() } else { self }
    }

    /// Tab bar shrinks while the user scrolls down, like Music and News.
    @ViewBuilder
    func rjTabBarMinimizeOnScroll() -> some View {
        if #available(iOS 26.0, *), !RJRuntime.isUITesting {
            self.tabBarMinimizeBehavior(.onScrollDown)
        } else { self }
    }

    /// Glass accessory above the tab bar (iOS 26). Nothing before.
    @ViewBuilder
    func rjTabAccessory<Accessory: View>(@ViewBuilder _ accessory: () -> Accessory) -> some View {
        let content = accessory()
        if #available(iOS 26.0, *) {
            self.tabViewBottomAccessory { content }
        } else { self }
    }

    /// Bottom or top bar that gets the scroll edge effect on iOS 26.
    @ViewBuilder
    func rjSafeAreaBar<Bar: View>(edge: VerticalEdge, @ViewBuilder _ bar: () -> Bar) -> some View {
        let content = bar()
        if #available(iOS 26.0, *) {
            self.safeAreaBar(edge: edge) { content }
        } else {
            self.safeAreaInset(edge: edge) { content }
        }
    }

    /// Forms in sheets let the iOS 26 glass sheet material show through.
    @ViewBuilder
    func rjSheetGlassForm() -> some View {
        if #available(iOS 26.0, *) { self.scrollContentBackground(.hidden) } else { self }
    }

    /// Before iOS 26 the bar background is hidden so the backdrop shows through.
    /// iOS 26 keeps the system scroll edge effect behind the glass bars.
    @ViewBuilder
    func rjNavigationBarChrome() -> some View {
        if #available(iOS 26.0, *) { self } else { self.toolbarBackground(.hidden, for: .navigationBar) }
    }
}

private struct RJLegacyGlass<S: Shape>: ViewModifier {
    let shape: S
    let tint: Color?
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content
            .background {
                if let tint { shape.fill(tint.opacity(0.22)) }
            }
            .background {
                if reduceTransparency {
                    shape.fill(Color(uiColor: .secondarySystemGroupedBackground))
                } else {
                    shape.fill(.regularMaterial)
                }
            }
            .overlay { shape.stroke(Color.white.opacity(0.16), lineWidth: 0.8).allowsHitTesting(false) }
    }
}

/// Groups neighbouring glass so it renders together and can blend and morph.
struct RJGlassGroup<Content: View>: View {
    var spacing: CGFloat = 16
    @ViewBuilder var content: () -> Content
    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content() }
        } else {
            content()
        }
    }
}

/// Settings-style label with a coloured rounded-square icon, as in the Settings app.
struct RJIconLabelStyle: LabelStyle {
    var color: Color
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 14) {
            configuration.icon
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(color.gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityHidden(true)
            configuration.title
        }
    }
}

extension LabelStyle where Self == RJIconLabelStyle {
    static func rjIcon(_ color: Color) -> RJIconLabelStyle { RJIconLabelStyle(color: color) }
}

/// Round glass icon button, optionally tinted when active (Liquid Glass "toggle").
struct RJGlassIconButton: View {
    let symbol: String
    let label: String
    var tint: Color? = nil
    var size: CGFloat = 44
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(tint == nil ? Color.primary : Color.white)
                .frame(width: size, height: size)
                .contentShape(Circle())
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .rjGlassSurface(Circle(), tint: tint, interactive: true)
        .accessibilityLabel(label)
    }
}

// MARK: - Tab bar accessory

/// Compact live status above the tab bar: freshness ring, server state, refresh and locate-all.
struct RJStatusAccessory: View {
    @Environment(AppModel.self) private var model
    @ObservedObject private var google = GoogleTrackerStore.shared

    private var refreshing: Bool {
        model.isRefreshingTrackers || model.isRefreshing
            || (model.showsGoogleControls && (google.isRefreshing || !google.locating.isEmpty))
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let now = Int(context.date.timeIntervalSince1970)
            let total = model.trackers.count
            let fresh = DashboardInsights.freshCount(model.trackers, now: now)
            HStack(spacing: 12) {
                ring(fraction: total > 0 ? Double(fresh) / Double(total) : 0)
                VStack(alignment: .leading, spacing: 1) {
                    Text(total == 0 ? "Keine Objekte" : "\(fresh) von \(total) aktuell")
                        .font(.subheadline.weight(.semibold))
                        .contentTransition(.numericText())
                    Text(statusLine).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 4)
                Button { Task { await refresh() } } label: {
                    Group {
                        if refreshing { ProgressView().controlSize(.small) } else { Image(systemName: "arrow.clockwise") }
                    }.frame(width: 34, height: 34).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(refreshing)
                .accessibilityLabel("Alles aktualisieren")
                .accessibilityIdentifier("accessory-refresh")
                if model.serverActionsAvailable {
                    Button { Task { await model.locateAll() } } label: {
                        Group {
                            if model.isLocatingAll { ProgressView().controlSize(.small) } else { Image(systemName: "location.fill") }
                        }.frame(width: 34, height: 34).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(model.isLocatingAll || !model.locatingRefs.isEmpty)
                    .accessibilityLabel("Alle Objekte orten")
                    .accessibilityIdentifier("accessory-locate-all")
                }
            }
            .font(.body.weight(.semibold))
            .padding(.horizontal, 14)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("status-accessory")
    }

    private var statusLine: String {
        if model.serverActionsAvailable, let date = model.lastRefresh {
            return "Server · Stand \(date.formatted(date: .omitted, time: .shortened))"
        }
        if model.connectionState == .restoring { return "Verbinde mit dem Server …" }
        if model.showsGoogleControls, google.hasCredentials { return "Google direkt auf diesem iPhone" }
        return "Offline · gespeicherte Standorte"
    }

    private func ring(fraction: Double) -> some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.12), lineWidth: 4)
            Circle().trim(from: 0, to: max(0.001, fraction))
                .stroke(RJBrand.gradient, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.smooth(duration: 0.6), value: fraction)
        }
        .frame(width: 24, height: 24)
        .accessibilityHidden(true)
    }

    private func refresh() async {
        Haptics.impact()
        async let local: Void = refreshGoogle()
        if model.connectionState == .connected { await model.refreshTrackers() }
        else if model.providerFilter != "google" || !google.hasCredentials { await model.retryServerConnection() }
        await local
    }

    private func refreshGoogle() async {
        if model.showsGoogleControls { await google.refreshLocations() }
    }
}

// MARK: - Search tab

/// Dedicated search tab (Tab role .search): on iOS 26 it becomes the separate glass search button.
struct TrackerSearchView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""

    private var results: [Tracker] {
        TrackerQuery(text: query, provider: "all", scope: .all, sort: .favorites, group: nil)
            .apply(to: model.trackers, origin: model.locationService.location)
    }

    var body: some View {
        List {
            if query.isEmpty {
                Section("Vorschläge") {
                    ForEach(results.prefix(8)) { tracker in row(tracker) }
                }
            } else {
                ForEach(results) { tracker in row(tracker) }
            }
        }
        .overlay {
            if !query.isEmpty && results.isEmpty { ContentUnavailableView.search(text: query) }
            else if model.trackers.isEmpty { ContentUnavailableView("Noch keine Objekte", systemImage: "airtag") }
        }
        .rjListChrome()
        .navigationTitle("Suchen")
        .searchable(text: $query, prompt: "Name, Adresse oder Notiz")
        .navigationDestination(for: String.self) { ref in
            if let tracker = model.trackers.first(where: { $0.ref == ref }) {
                TrackerDetailView(tracker: tracker)
            } else {
                ContentUnavailableView("Objekt nicht verfügbar", systemImage: "airtag")
            }
        }
    }

    private func row(_ tracker: Tracker) -> some View {
        NavigationLink(value: tracker.ref) {
            HStack(spacing: 12) {
                Text(tracker.emoji ?? "📍").font(.title2)
                    .frame(width: 40, height: 40)
                    .background(tracker.provider.rjProviderColor.opacity(0.16).gradient, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(tracker.name).font(.body.weight(.semibold))
                    HStack(spacing: 4) {
                        Text(tracker.location?.address?.locality ?? tracker.provider.rjProviderName)
                        Text("·")
                        FreshnessLabel(timestamp: tracker.reportTimestamp > 0 ? tracker.reportTimestamp : nil)
                    }.font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityIdentifier("search-result-\(tracker.ref)")
    }
}
