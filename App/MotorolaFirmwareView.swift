import SwiftUI
import UniformTypeIdentifiers
import SpotIntegration

struct MotorolaFirmwareView: View {
    let deviceID: String
    @Environment(\.rjExpandInspector) private var expandInspector
    @ObservedObject private var updater = MotorolaFirmwareUpdater.shared
    @ObservedObject private var google = GoogleTrackerStore.shared
    @State private var importing = false
    @State private var confirming = false
    private var model: MotorolaTagModel? { google.motorolaModel(deviceID) }
    private var info: MotorolaHardwareInfo? { updater.inspectedDeviceID == deviceID ? updater.info : nil }

    var body: some View {
        Form {
            Section {
                Label("Moto Tag · Firmware", systemImage: "sensor.tag.radiowaves.forward.fill").font(.headline)
                Text(model?.rawValue ?? "Unbekanntes Modell").font(.subheadline).foregroundStyle(.secondary)
                Text("Experimenteller iPhone-Updater für Moto Tag XT2445-1. Der Funkablauf wurde aus der Motorola-App rekonstruiert und noch nicht an echter Hardware bestätigt.").font(.footnote)
                    .accessibilityIdentifier("motorola-firmware-hardware-limit")
                if model == .secondGeneration {
                    Text("XT2561-1 verwendet ein anderes Updateformat. Installation auf diesem Modell ist noch nicht verfügbar.").font(.footnote).foregroundStyle(.orange)
                }
            }
            Section("1 · Originalfirmware") {
                if let package = updater.package {
                    LabeledContent("Importiertes Original", value: package.version)
                    LabeledContent("Passendes Modell", value: package.model.rawValue)
                    Label("Dateiprüfsumme bestätigt", systemImage: "checkmark.shield.fill").foregroundStyle(.green)
                }
                Button("Motorola-Originaldatei importieren", systemImage: "square.and.arrow.down") { importing = true }
                    .disabled(updater.busy).accessibilityIdentifier("motorola-firmware-import")
                Text("Akzeptiert Moto Tag APK/APKM 01.01.101.23 oder dessen unveränderte OTA.bin (2.0.104). Die Android-App wird dabei nicht installiert. Neuere oder fremde Firmware wird erst nach Prüfung freigegeben.").font(.caption).foregroundStyle(.secondary)
                Link("Moto-Tag-Downloads öffnen", destination: URL(string: "https://www.apkmirror.com/apk/motorola-mobility-llc/moto-tag/")!)
                Text("Eine automatische Abfrage neuester Motorola-Serverupdates ist noch nicht integriert. Die importierte Version ist kein Nachweis, dass es kein neueres Update gibt.").font(.caption).foregroundStyle(.secondary)
            }
            Section("2 · Deinen Tag prüfen") {
                Button("Eigentümer, Firmware und Batterie prüfen", systemImage: "checkmark.shield") {
                    Task { await updater.inspect(deviceID) }
                }.disabled(updater.busy || model == nil)
                    .accessibilityIdentifier("motorola-firmware-inspect")
                if let info {
                    LabeledContent("Firmware auf dem Tag", value: info.firmware)
                    LabeledContent("Batterie", value: "\(info.battery) %")
                    LabeledContent("Hardware", value: info.hardware)
                    if let package = updater.package,
                       let current = MotorolaFirmwarePolicy.version(info.firmware),
                       let available = MotorolaFirmwarePolicy.version(package.version), !current.lexicographicallyPrecedes(available) {
                        Text("Das importierte Original ist nicht neuer als deine Firmware.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text("Tag direkt neben das iPhone legen und Verbindungen der Motorola-App auf anderen Geräten beenden. Nur der bestätigte Eigentümer kann aktualisieren; Freigabezugriff reicht nicht.").font(.caption).foregroundStyle(.secondary)
            }
            Section("3 · Aktualisieren") {
                Button("Originalfirmware installieren", systemImage: "arrow.triangle.2.circlepath") { confirming = true }
                    .disabled(!updater.canInstall(deviceID)).accessibilityIdentifier("motorola-firmware-install")
                if updater.updating {
                    ProgressView(value: updater.progress)
                    Text("Übertragen: \(Int(updater.progress * 100)) %").monospacedDigit()
                    if updater.canCancel { Button("Upload abbrechen", role: .destructive) { updater.cancelUpload() } }
                } else if updater.busy { ProgressView() }
                Text(updater.status).font(.footnote)
                if let error = updater.errorMessage { Text(error).font(.footnote).foregroundStyle(.orange).textSelection(.enabled) }
                Text("Während des Updates App geöffnet lassen und Tag nicht ausschalten. Erfolg wird erst nach dem Neustart und dem erneuten Auslesen der Firmware gemeldet.").font(.caption).foregroundStyle(.secondary)
            }
            Section("UWB auf dem iPhone") {
                Text("Firmware 2.0.104 macht den Moto Tag nicht automatisch zu Apple-kompatiblem UWB-Zubehör. Die Google-Fähigkeitsprüfung bleibt verfügbar; eine echte UWB-Pfeilortung für diesen Tag ist noch nicht implementiert.").font(.footnote)
            }
        }
        .rjListChrome().navigationTitle("Motorola-Firmware").navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(updater.updating)
        .interactiveDismissDisabled(updater.updating)
        .onAppear { expandInspector(); if !updater.updating { google.beginNearby(deviceID) } }
        .onDisappear { google.endNearby() }
        .sheet(isPresented: $importing) {
            AnyDocumentPicker(onPick: { url in
                importing = false
                Task { await updater.importFile(url) }
            }, onCancel: { importing = false })
                .ignoresSafeArea()
        }
        .alert("Moto Tag aktualisieren?", isPresented: $confirming) {
            Button("Installieren") { Task { await updater.install(deviceID) } }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Die geprüfte Motorola-Originalfirmware 2.0.104 wird auf deinen XT2445-1 übertragen. Batterie und Modell werden vorher erneut geprüft. Der iPhone-Updatepfad ist experimentell.")
        }
    }
}
