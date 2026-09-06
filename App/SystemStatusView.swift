import SwiftUI

struct SystemStatusView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        List {
            Section("Verbindung") {
                SyncStatusView()
                LabeledContent("Server", value: model.bootstrap?.api?.serverName ?? "Universal Tag Studio")
                LabeledContent("Version", value: model.bootstrap?.api?.serverVersion ?? "–")
                if let date = model.lastRefresh { LabeledContent("Synchronisiert") { Text(date.rjTimelineText) } }
            }
            Section("Ortungsnetzwerke") {
                ForEach(["apple", "google", "samsung"], id: \.self) { provider in
                    let health = model.bootstrap?.providers?[provider] ?? .null
                    HStack(spacing: 12) {
                        Image(systemName: "antenna.radiowaves.left.and.right").foregroundStyle(health["connected"].boolValue == true ? .green : .secondary)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(provider.capitalized).font(.headline)
                            Text(health["status"].stringValue ?? "Kein Status verfügbar").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(health["devices"].integer) Objekte").font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 4)
                }
            }
            Section("Server verwalten") {
                NavigationLink { PollingSettingsView() } label: { Label("Ortungsintervalle", systemImage: "timer") }
                NavigationLink { DiagnosticsView() } label: { Label("System prüfen", systemImage: "stethoscope") }
                NavigationLink { ServerStorageView() } label: { Label("Speicherübersicht", systemImage: "externaldrive") }
            }
            Section("Benachrichtigungen") {
                LabeledContent("APNs", value: model.bootstrap?.push?.serverConfigured == true ? "Bereit" : "Nicht eingerichtet")
                LabeledContent("Registrierte iPhones", value: "\(model.bootstrap?.push?.activeDevices ?? 0)")
            }
        }
        .navigationTitle("Serverzentrale").navigationBarTitleDisplayMode(.inline)
        .refreshable { await model.refresh() }
    }
}

struct PollingSettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var intervals: [String: PollingInterval] = [:]
    @State private var busy = false
    @State private var error: String?
    @State private var saved = false
    private let providers = ["apple", "google", "samsung"]
    var body: some View {
        Form {
            Section {
                Text("Lege fest, wie häufig dein Server die Netzwerke abfragt. Die Intervalle gelten für alle verbundenen Geräte und Nutzer.").font(.subheadline).foregroundStyle(.secondary)
            }
            if let error { Text(error).foregroundStyle(.red) }
            if intervals.isEmpty { ProgressView("Intervalle laden …") }
            ForEach(providers, id: \.self) { provider in
                if let value = intervals[provider] {
                    Section(provider.capitalized) {
                        Stepper("Mindestens \(value.minimum) Sekunden", value: binding(provider, minimum: true), in: PollingInterval.bounds(for: provider))
                        Stepper("Höchstens \(value.maximum) Sekunden", value: binding(provider, minimum: false), in: PollingInterval.bounds(for: provider))
                        if !value.isValid(for: provider) { Text("Das Maximum muss mindestens dem Minimum entsprechen.").font(.caption).foregroundStyle(.red) }
                    }
                }
            }
            if saved { Label("Intervalle gespeichert", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
        }
        .navigationTitle("Ortungsintervalle").navigationBarTitleDisplayMode(.inline)
        .disabled(busy)
        .toolbar { Button("Sichern") { Task { await save() } }.disabled(busy || intervals.count != 3 || !providers.allSatisfy { intervals[$0]?.isValid(for: $0) == true }) }
        .task { await load() }
        .refreshable { await load() }
    }
    private func binding(_ provider: String, minimum: Bool) -> Binding<Int> {
        Binding(get: { minimum ? intervals[provider]?.minimum ?? 30 : intervals[provider]?.maximum ?? 60 }, set: { value in
            if minimum { intervals[provider]?.minimum = value } else { intervals[provider]?.maximum = value }; saved = false
        })
    }
    private func load() async {
        busy = true; defer { busy = false }; error = nil
        do {
            let result = try await APIClient.shared.requestJSON(path: "/api/polling/settings")
            for provider in providers {
                let value = result["polling"]["providers"][provider]
                guard value["interval_min"].numberValue != nil, value["interval_max"].numberValue != nil else { throw APIError.message("Der Server liefert keine vollständigen Intervalle.") }
                intervals[provider] = .init(minimum: value["interval_min"].integer, maximum: value["interval_max"].integer)
            }
        } catch { self.error = error.localizedDescription }
    }
    private func save() async {
        busy = true; defer { busy = false }; error = nil
        do {
            let payload = intervals.mapValues { ["interval_min": $0.minimum, "interval_max": $0.maximum] }
            _ = try await APIClient.shared.requestJSON(path: "/api/polling/settings", method: "POST", json: payload)
            saved = true; await model.refresh()
        } catch { self.error = error.localizedDescription }
    }
}

struct DiagnosticsView: View {
    @State private var report: JSONValue = .null
    @State private var error: String?
    @State private var running = false
    @State private var requestID = UUID()
    var body: some View {
        List {
            Section {
                Text("Prüft Verbindungen, Konfiguration und Serverfunktionen. Die Ergebnisse helfen dir, fehlende Standorte einzugrenzen.").foregroundStyle(.secondary)
                Button { running = true; requestID = UUID() } label: { Label("Schnellprüfung starten", systemImage: "stethoscope") }.disabled(running)
                if running { ProgressView("Prüfung läuft …") }
                if let error { Text(error).foregroundStyle(.red) }
            }
            ForEach(Array(report["checks"].arrayValue.enumerated()), id: \.offset) { _, check in
                Section {
                    Label(check["title"].stringValue ?? "Prüfung", systemImage: check["status"].stringValue == "ok" ? "checkmark.circle.fill" : "info.circle")
                        .font(.headline).foregroundStyle(check["status"].stringValue == "ok" ? .green : .primary)
                    Text(check["summary"].stringValue ?? "")
                    if let detail = check["detail"].stringValue, !detail.isEmpty { Text(detail).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
                }
            }
            if report["checks"].arrayValue.isEmpty && !running { Text("Noch keine Prüfergebnisse. Starte eine Schnellprüfung.").foregroundStyle(.secondary) }
        }
        .navigationTitle("System prüfen").navigationBarTitleDisplayMode(.inline)
        .task(id: requestID) { await load(start: running) }
        .refreshable { if !running { await load(start: false) } }
    }
    private func load(start: Bool) async {
        error = nil
        defer { running = false }
        do {
            if start { _ = try await APIClient.shared.requestJSON(path: "/api/diagnostics/run", method: "POST", json: ["deep": false]) }
            for _ in 0..<30 {
                try Task.checkCancellation()
                report = try await APIClient.shared.requestJSON(path: "/api/diagnostics")
                guard report["status"].stringValue == "running" else { return }
                running = true
                try await Task.sleep(for: .seconds(2))
            }
            error = "Die Prüfung läuft auf dem Server weiter. Aktualisiere später erneut."
        } catch is CancellationError { } catch { self.error = error.localizedDescription }
    }
}

struct ServerStorageView: View {
    @State private var data: JSONValue = .null
    @State private var error: String?
    @State private var loading = false
    var body: some View {
        List {
            if loading { ProgressView("Speicher laden …") }
            if let error { Text(error).foregroundStyle(.red) }
            Section("Serverlaufwerk") {
                let total = data["disk"]["total"].numberValue ?? 0
                let used = data["disk"]["used"].numberValue ?? 0
                if total > 0 { ProgressView(value: min(used, total), total: total).tint(.blue) }
                LabeledContent("Belegt", value: bytes(data["disk"]["used"]))
                LabeledContent("Frei", value: bytes(data["disk"]["free"]))
                LabeledContent("Tracker-Daten", value: bytes(data["bytes"]["total"]))
            }
            Section("Daten nach Kategorie") {
                ForEach(Array(data["categories"].arrayValue.enumerated()), id: \.offset) { _, category in
                    LabeledContent(category["label"].stringValue ?? category["id"].stringValue ?? "Daten", value: bytes(category["bytes"]))
                }
            }
        }
        .navigationTitle("Speicher").navigationBarTitleDisplayMode(.inline)
        .task { await load() }.refreshable { await load() }
    }
    private func bytes(_ value: JSONValue) -> String { value.numberValue == nil ? "–" : ByteCountFormatter.string(fromByteCount: Int64(value.integer), countStyle: .file) }
    private func load() async {
        loading = true; defer { loading = false }; error = nil
        do { data = try await APIClient.shared.requestJSON(path: "/api/v2/storage") } catch { self.error = error.localizedDescription }
    }
}
