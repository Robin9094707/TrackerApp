import SwiftUI

// MARK: - 8.0 Fusion network priority

/// Lets the owner decide which network of a fusion is shown first and which
/// networks only act as backup for newer reports. Stored on the server as the
/// additive `network_policy` of the fusion profile.
struct FusionNetworkPolicyView: View {
    @Environment(AppModel.self) private var model
    let tracker: Tracker

    @State private var mode = "newest"
    @State private var order: [String] = []
    @State private var backupAfter = 10
    @State private var backupPolling = "always"
    @State private var shownSource: String?
    @State private var sourceTimes: [String: Int] = [:]
    @State private var loading = true
    @State private var saving = false
    @State private var message: String?
    @State private var failed = false

    private static let modes: [(id: String, title: String, detail: String, symbol: String)] = [
        ("newest", "Neuester Report", "Zeigt immer die jüngste Meldung aller Netze.", "clock.badge.checkmark"),
        ("priority", "Priorität mit Backup", "Bevorzugt das Hauptnetz. Backups springen ein, wenn sie deutlich neuer sind.", "list.number"),
        ("primary_only", "Nur Hauptnetz", "Zeigt nur das Hauptnetz. Andere Netze nur, wenn es noch nie gemeldet hat.", "1.circle"),
    ]

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Image(systemName: "point.3.connected.trianglepath.dotted")
                        .font(.title2.weight(.semibold)).foregroundStyle(.white)
                        .frame(width: 50, height: 50)
                        .background(RJBrand.gradient, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(tracker.name).font(.headline)
                        Text("Welches Netz zählt zuerst?").font(.subheadline).foregroundStyle(.secondary)
                    }
                }.padding(.vertical, 4)
            }

            if loading {
                Section { HStack { ProgressView(); Text("Netze werden geladen …").foregroundStyle(.secondary) } }
            } else {
                Section("Netze") {
                    ForEach(Array(order.enumerated()), id: \.element) { index, provider in
                        HStack(spacing: 12) {
                            Text("\(index + 1)")
                                .font(.caption.weight(.heavy)).foregroundStyle(.white)
                                .frame(width: 24, height: 24)
                                .background(provider.rjProviderColor.gradient, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(provider.rjProviderName).font(.subheadline.weight(.semibold))
                                    if provider == shownSource {
                                        Text("Angezeigt").font(.caption2.weight(.bold)).foregroundStyle(.green)
                                            .padding(.horizontal, 6).padding(.vertical, 2)
                                            .background(Color.green.opacity(0.14), in: Capsule())
                                    }
                                }
                                if let timestamp = sourceTimes[provider], timestamp > 0 {
                                    FreshnessLabel(timestamp: timestamp)
                                } else {
                                    Text("Keine Meldung").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if mode != "newest" {
                                Text(index == 0 ? "Hauptnetz" : "Backup").font(.caption).foregroundStyle(.secondary)
                                Button { move(index, by: -1) } label: { Image(systemName: "chevron.up") }
                                    .buttonStyle(.borderless).disabled(index == 0)
                                    .accessibilityLabel("\(provider.rjProviderName) nach oben")
                                Button { move(index, by: 1) } label: { Image(systemName: "chevron.down") }
                                    .buttonStyle(.borderless).disabled(index == order.count - 1)
                                    .accessibilityLabel("\(provider.rjProviderName) nach unten")
                            }
                        }
                    }
                }

                Section("Modus") {
                    ForEach(Self.modes, id: \.id) { option in
                        Button {
                            withAnimation(.snappy) { mode = option.id }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: option.symbol).frame(width: 26).foregroundStyle(.tint)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(option.title).font(.body.weight(.medium)).foregroundStyle(.primary)
                                    Text(option.detail).font(.caption).foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer()
                                if mode == option.id { Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint) }
                            }.contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }

                if mode == "priority" {
                    Section {
                        Stepper(value: $backupAfter, in: 1...240) {
                            Text("Backup nach \(backupAfter) Min. Vorsprung")
                        }
                    } footer: {
                        Text("Ein Backup-Netz wird angezeigt, sobald seine Meldung so viel neuer ist als die des Hauptnetzes.")
                    }
                }

                if mode != "newest" {
                    Section {
                        Picker("Backup-Netze abfragen", selection: $backupPolling) {
                            Text("Immer – meiste Reports").tag("always")
                            Text("Nur wenn Hauptnetz veraltet").tag("when_stale")
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                    } header: {
                        Text("Backup-Abfrage")
                    } footer: {
                        Text("„Immer“ sammelt parallel aus allen Netzen. „Nur wenn veraltet“ schont Konten und Akku und startet Backups erst nach der Wartezeit.")
                    }
                }

                Section {
                    Button {
                        Task { await save() }
                    } label: {
                        HStack {
                            Spacer()
                            if saving { ProgressView().tint(.white) } else { Text("Speichern").fontWeight(.semibold) }
                            Spacer()
                        }
                    }
                    .listRowBackground(RJBrand.gradient)
                    .foregroundStyle(.white)
                    .disabled(saving)
                    if let message {
                        Label(message, systemImage: failed ? "exclamationmark.triangle" : "checkmark.circle")
                            .font(.footnote).foregroundStyle(failed ? .red : .secondary)
                    }
                }
            }
        }
        .rjFormChrome()
        .navigationTitle("Netz-Priorität")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func move(_ index: Int, by offset: Int) {
        let target = index + offset
        guard order.indices.contains(index), order.indices.contains(target) else { return }
        withAnimation(.snappy) { order.swapAt(index, target) }
        Haptics.impact()
    }

    private func apply(_ response: JSONValue) {
        let policy = response["policy"]
        mode = policy["mode"].stringValue ?? "newest"
        let received = policy["order"].arrayValue.compactMap(\.stringValue)
        order = received.isEmpty ? tracker.fusionNetworkNames : received
        backupAfter = max(1, min(240, policy["backup_after_minutes"].integer == 0 ? 10 : policy["backup_after_minutes"].integer))
        backupPolling = policy["backup_polling"].stringValue ?? "always"
        shownSource = response["selection"]["source"].stringValue
        var times: [String: Int] = [:]
        for (provider, value) in response["source_locations"].objectValue ?? [:] {
            let timestamp = value["ts"].numberValue ?? value["timestamp"].numberValue ?? 0
            times[provider] = Int(timestamp)
        }
        sourceTimes = times
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            let response = try await model.serverJSON("/api/mobile/v1/fusion-networks", query: [URLQueryItem(name: "ref", value: tracker.ref)])
            apply(response)
            message = nil
        } catch {
            order = tracker.fusionNetworkNames
            failed = true
            message = "Der Server unterstützt die Netz-Priorität noch nicht. Bitte Backend 22.0 installieren."
        }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        do {
            let response = try await model.serverJSON(
                "/api/mobile/v1/fusion-networks", method: "PUT",
                json: ["mode": mode, "order": order, "backup_after_minutes": backupAfter, "backup_polling": backupPolling],
                query: [URLQueryItem(name: "ref", value: tracker.ref)])
            apply(response)
            failed = false
            message = "Gespeichert."
            Haptics.success()
            await model.refreshTrackers()
        } catch {
            failed = true
            message = error.localizedDescription
            Haptics.warning()
        }
    }
}

extension Tracker {
    /// Human readable summary of the fusion's network policy for list rows.
    var networkPolicySummary: String {
        guard provider == "fusion" else { return "" }
        let policy = networkPolicy
        switch policy?["mode"].stringValue ?? "newest" {
        case "priority":
            let primary = policy?["order"].arrayValue.first?.stringValue ?? "apple"
            return "Priorität: \(primary.rjProviderName) zuerst, Rest als Backup"
        case "primary_only":
            let primary = policy?["order"].arrayValue.first?.stringValue ?? "apple"
            return "Nur \(primary.rjProviderName)"
        default:
            return "Neuester Report aller Netze"
        }
    }
}

// MARK: - 8.0 Bags (Taschen) for every tracker, fusions included

struct BagToggleButton: View {
    @Environment(AppModel.self) private var model
    let tracker: Tracker
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        let isBag = tracker.schoolBag == true
        Button {
            Task { await toggle(!isBag) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isBag ? "backpack.fill" : "backpack")
                    .font(.title3).foregroundStyle(isBag ? .white : Color.indigo)
                    .frame(width: 34, height: 34)
                    .background(isBag ? AnyShapeStyle(RJBrand.gradient) : AnyShapeStyle(Color.indigo.opacity(0.12)),
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(isBag ? "Ist eine Tasche" : "Als Tasche festlegen").font(.body.weight(.semibold)).foregroundStyle(.primary)
                    Text(error ?? (isBag ? "Verlauf wird dauerhaft gesammelt. Tippen zum Entfernen." : "Auch für Fusionen: alle Netze sammeln den Verlauf."))
                        .font(.caption).foregroundStyle(error == nil ? Color.secondary : Color.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if busy { ProgressView() } else {
                    Image(systemName: isBag ? "checkmark.circle.fill" : "plus.circle")
                        .font(.title3).foregroundStyle(isBag ? Color.green : Color.accentColor)
                }
            }.contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .accessibilityIdentifier("bag-toggle-\(tracker.ref)")
    }

    private func toggle(_ enabled: Bool) async {
        busy = true
        defer { busy = false }
        do {
            _ = try await model.serverJSON("/api/mobile/v1/bags", method: "POST", json: ["ref": tracker.ref, "enabled": enabled])
            error = nil
            Haptics.success()
            await model.refreshTrackers()
        } catch {
            self.error = "Nicht gespeichert: \(error.localizedDescription)"
            Haptics.warning()
        }
    }
}
