import SwiftUI

struct MoreView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                profileHeader
                trackingCard
                serverCard
                appCard
            }
            .padding(16)
            .padding(.bottom, 28)
        }
        .rjScreenChrome()
        .navigationTitle("Ich")
        .navigationBarTitleDisplayMode(.large)
        .refreshable { await model.refresh() }
    }

    private var profileHeader: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(Color.accentColor.opacity(0.14))
                Image(systemName: "person.fill")
                    .font(.title)
                    .foregroundStyle(.tint)
            }
            .frame(width: 58, height: 58)

            VStack(alignment: .leading, spacing: 4) {
                Text(model.bootstrap?.session?.user?.displayName ?? model.username)
                    .font(.title2.bold())
                HStack(spacing: 7) {
                    RJStatusPill(text: "Verbunden", symbol: "checkmark.circle.fill", tint: .green)
                    Text("\(model.trackers.count) Tracker")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .rjCard()
    }

    private var trackingCard: some View {
        VStack(spacing: 0) {
            RJSectionTitle(title: "Tracking", subtitle: "Orte, Geofences und Automationen", symbol: "location.fill")
                .padding(.bottom, 10)
            Divider()
            menuRow("Geofences", subtitle: "\(model.bootstrap?.geofences?.count ?? 0) Bereiche", symbol: "mappin.and.ellipse") { GeofencesView() }
            Divider().padding(.leading, 46)
            menuRow("Gespeicherte Orte", subtitle: "\(model.bootstrap?.savedPlaces?.count ?? 0) Orte", symbol: "star.circle.fill") { SavedPlacesView() }
        }
        .rjCard()
    }

    private var serverCard: some View {
        VStack(spacing: 0) {
            RJSectionTitle(title: "Server", subtitle: model.bootstrap?.api?.serverName ?? "Universal Tag Studio", symbol: "server.rack")
                .padding(.bottom, 10)
            Divider()
            menuRow("Web Studio", subtitle: "Alle Server-Funktionen", symbol: "safari.fill") { WebStudioView() }
            Divider().padding(.leading, 46)
            menuRow("Systemstatus", subtitle: model.bootstrap?.push?.serverConfigured == true ? "APNs bereit" : "Status & Provider", symbol: "waveform.path.ecg.rectangle") { SystemStatusView() }
            Divider().padding(.leading, 46)
            menuRow("API-Werkzeuge", subtitle: "Erweiterte Server-Steuerung", symbol: "terminal.fill") { AdvancedToolsView() }
            Divider().padding(.leading, 46)
            menuRow("Debug-Protokoll", subtitle: "Diagnose der App", symbol: "ladybug.fill") { DebugConsoleView() }
        }
        .rjCard()
    }

    private var appCard: some View {
        VStack(spacing: 0) {
            RJSectionTitle(title: "App", subtitle: "Verbindung, Push und Datenschutz", symbol: "iphone")
                .padding(.bottom, 10)
            Divider()
            menuRow("Einstellungen", subtitle: "Server & Benachrichtigungen", symbol: "gearshape.fill") { SettingsView() }
        }
        .rjCard()
    }

    private func menuRow<Destination: View>(
        _ title: String,
        subtitle: String,
        symbol: String,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        NavigationLink(destination: destination()) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.headline)
                    .foregroundStyle(.tint)
                    .frame(width: 34, height: 34)
                    .background(Color.accentColor.opacity(0.11), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
