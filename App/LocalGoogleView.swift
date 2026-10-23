import SwiftUI
import SpotIntegration

struct LocalGoogleDestination: Identifiable {
    let id = UUID()
    var deviceID: String? = nil
}

struct LocalGoogleView: View {
    var deviceID: String? = nil
    var body: some View { GoogleTrackerExperience(initialDeviceID: deviceID) }
}

struct GoogleLauncherCard: View {
    var deviceID: String? = nil
    @ObservedObject private var google = GoogleTrackerStore.shared
    @State private var open = false
    var body: some View {
        Button { open = true } label: {
            HStack(spacing: 14) {
                Image(systemName: "sensor.tag.radiowaves.forward.fill")
                    .font(.title2).foregroundStyle(.green)
                    .frame(width: 50, height: 50).background(.green.opacity(0.10), in: RoundedRectangle(cornerRadius: 15))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Google Find Hub").font(.headline).foregroundStyle(.primary)
                    Text(google.account == nil ? "Direkt anmelden · ohne Server" : "\(google.trackers.count) Objekte · auf diesem iPhone")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.secondary)
            }.padding(.vertical, 6).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("local-google-launcher")
        .fullScreenCover(isPresented: $open) { LocalGoogleView(deviceID: deviceID) }
    }
}

struct LocalGoogleRows: View {
    @Environment(AppModel.self) private var model
    @ObservedObject private var google = GoogleTrackerStore.shared
    @State private var destination: LocalGoogleDestination?
    private var trackers: [GoogleTrackerSnapshot] {
        guard ["all", "google"].contains(model.providerFilter), model.selectedScope == .all,
              model.selectedGroup == nil else { return [] }
        return google.trackers.filter { model.searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(model.searchText) }
    }
    var body: some View {
        Section {
            GoogleLauncherCard()
            ForEach(trackers) { tracker in
                Button { destination = LocalGoogleDestination(deviceID: tracker.id) } label: {
                    HStack(spacing: 14) {
                        AsyncImage(url: URL(string: tracker.imageURL)) { image in
                            if let image = image.image { image.resizable().scaledToFit() }
                            else { Image(systemName: "sensor.tag.radiowaves.forward.fill").font(.title2).foregroundStyle(.green) }
                        }.frame(width: 48, height: 48)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(tracker.name).font(.headline).foregroundStyle(.primary)
                            Label(tracker.nearby ? "In der Nähe · Bluetooth" : "Google · direkt verbunden",
                                  systemImage: tracker.nearby ? "dot.radiowaves.left.and.right" : "lock.iphone")
                                .font(.caption).foregroundStyle(tracker.nearby ? Color.green : .secondary)
                            if let date = tracker.reportedAt {
                                Text(date, style: .relative).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
                    }.padding(.vertical, 5).contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
            if let error = google.errorMessage { Text(error).font(.caption).foregroundStyle(.orange) }
        } header: { Text("Google auf diesem iPhone") }
        .fullScreenCover(item: $destination) { LocalGoogleView(deviceID: $0.deviceID) }
    }
}
