import SwiftUI
import NearbyInteraction
import SpotIntegration

struct GoogleUWBLabView: View {
    let deviceID: String
    @Environment(\.rjExpandInspector) private var expandInspector
    @ObservedObject private var google = GoogleTrackerStore.shared
    @State private var busy = false
    @State private var result: GoogleUWBCapabilities?
    @State private var message: String?
    private var tracker: GoogleTrackerSnapshot? { google.trackers.first { $0.id == deviceID } }
    private var phoneUWB: Bool { NISession.deviceCapabilities.supportsPreciseDistanceMeasurement }
    private var phoneDirection: Bool { NISession.deviceCapabilities.supportsDirectionMeasurement }

    var body: some View {
        Form {
            Section {
                Label("UWB-Prüfung · experimentell", systemImage: "dot.scope").font(.headline)
                Text("UWB-Pfeil für Google-Tracker noch nicht verfügbar").font(.subheadline.bold())
                    .accessibilityIdentifier("uwb-compatibility-status")
                Text("Diese Prüfung liest Fähigkeiten deines eigenen Trackers. Sie startet keine UWB-Ortung. Bluetooth-Signalstärke liefert keinen Richtungspfeil und keine genaue Entfernung.").font(.footnote).foregroundStyle(.secondary)
            }
            Section("Dieses iPhone") {
                LabeledContent("Präzise Entfernung", value: phoneUWB ? "Vom System unterstützt" : "Nicht verfügbar")
                LabeledContent("Richtungsmessung", value: phoneDirection ? "Vom System unterstützt" : "Nicht verfügbar")
                Text("Die iPhone-Fähigkeit bestätigt noch keine Kompatibilität mit deinem Moto Tag.").font(.caption).foregroundStyle(.secondary)
            }
            Section(tracker?.name ?? "Eigener Google-Tracker") {
                Label(tracker?.nearby == true ? "Bluetooth-Signal empfangen" : "Tracker in Bluetooth-Reichweite bringen", systemImage: "antenna.radiowaves.left.and.right")
                Button {
                    busy = true; result = nil; message = nil
                    Task { @MainActor in
                        defer { busy = false }
                        do { result = try await google.probeUWBCapabilities(deviceID) }
                        catch { message = error.localizedDescription }
                    }
                } label: {
                    if busy { ProgressView("Fähigkeiten werden abgefragt …") }
                    else { Text("Fähigkeiten des Trackers prüfen") }
                }.disabled(busy || tracker?.nearby != true)
                if let result {
                    LabeledContent("UWB-Antwort", value: result.supportsUWB ? "Vom Tracker bestätigt" : "In dieser Antwort nicht angeboten")
                    if result.supportsUWB {
                        LabeledContent("Kanäle", value: result.channels.map(String.init).joined(separator: ", "))
                        LabeledContent("Konfigurations-IDs", value: result.configIDs.map(String.init).joined(separator: ", "))
                        if let interval = result.minimumIntervalMS { LabeledContent("Minimales Intervall", value: "\(interval) ms") }
                        LabeledContent("Initiator-Rolle", value: result.supportsInitiator ? "Unterstützt" : "Nicht bestätigt")
                    }
                }
                if let message { Text(message).font(.footnote).foregroundStyle(.orange).textSelection(.enabled) }
            }
            if google.motorolaModel(deviceID) != nil {
                Section("Motorola-Firmware") {
                    NavigationLink { MotorolaFirmwareView(deviceID: deviceID) } label: {
                        Label("Firmware auf dem Tag prüfen", systemImage: "arrow.down.circle")
                    }
                    Text("Ein Firmwareupdate allein bestätigt keine UWB-Kompatibilität mit diesem iPhone.").font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Warum noch kein Pfeil?") {
                Text("Google und Apple müssen dieselbe UWB-Sitzung aufbauen können. Für den Moto Tag ist eine funktionierende Verbindung zwischen Googles Sitzungsdaten und Apples Nearby Interaction derzeit nicht nachgewiesen. Ein vorhandener UWB-Chip allein reicht dafür nicht.").font(.footnote)
                Text("Bei älterer Moto-Tag-Firmware kann auch die Fähigkeitsabfrage ausbleiben. Ein Fehler bedeutet deshalb nicht automatisch, dass der Tracker kein UWB hat.").font(.caption).foregroundStyle(.secondary)
                ShareLink(item: diagnosticText) { Label("Prüfergebnis teilen", systemImage: "square.and.arrow.up") }
            }
        }
        .rjListChrome().navigationTitle("UWB-Labor").navigationBarTitleDisplayMode(.inline)
        .onAppear { expandInspector(); google.beginNearby(deviceID) }
        .onChange(of: tracker?.nearby) { _, nearby in if nearby == true { google.beginNearby(deviceID) } }
        .onDisappear { google.endNearby() }
    }
    private var diagnosticText: String {
        "RJ Tracker UWB-Prüfung\niPhone Entfernung: \(phoneUWB)\niPhone Richtung: \(phoneDirection)\n" +
        "Tracker UWB-Antwort: \(result.map { String($0.supportsUWB) } ?? "unbekannt")\n" +
        "Kanäle: \(result?.channels.map(String.init).joined(separator: ", ") ?? "unbekannt")\n" +
        "Konfigurations-IDs: \(result?.configIDs.map(String.init).joined(separator: ", ") ?? "unbekannt")\n" +
        "UWB-Ortung nicht implementiert; kein Richtungspfeil.\n\(message ?? "")"
    }
}
