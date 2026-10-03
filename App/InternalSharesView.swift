import SwiftUI
import MapKit

struct InternalSharesView: View {
    @State private var snapshot: JSONValue = .null
    @State private var error: String?
    var body: some View {
        List {
            NavigationLink("Tracker intern freigeben") { InternalShareEditor(snapshot: snapshot) }.disabled(snapshot.objectValue == nil)
            ForEach(["received", "outgoing"], id: \.self) { direction in
                Section(direction == "received" ? "Mit mir geteilt" : "Von mir geteilt") {
                    ForEach(snapshot[direction].rows, id: \.identifier) { share in
                        NavigationLink { InternalShareDetail(initial: share, snapshot: snapshot) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(share["label"].text).font(.headline)
                                Text(share[direction == "received" ? "owner" : "recipient"]["display_name"].text).font(.caption).foregroundStyle(.secondary)
                                if share["active"].boolValue == false { Text("Pausiert").font(.caption).foregroundStyle(.orange) }
                            }
                        }
                    }
                    if snapshot[direction].rows.isEmpty { Text("Keine Freigaben").foregroundStyle(.secondary) }
                }
            }
            if let error { Text(error).foregroundStyle(.red) }
        }.scrollContentBackground(.hidden).rjScreenChrome().navigationTitle("Interne Freigaben").navigationBarTitleDisplayMode(.inline)
        .task { await load() }.refreshable { await load() }
    }
    private func load() async { do { snapshot = try await APIClient.shared.requestJSON(path: "/api/internal-shares", query: [.init(name: "history", value: "0")]); error = nil } catch { self.error = error.localizedDescription } }
}

struct InternalShareEditor: View {
    let snapshot: JSONValue
    var share: JSONValue = .null
    @State private var tracker = ""
    @State private var recipient = ""
    @State private var permissions: [String: Bool] = ["can_locate": true, "show_history": false, "show_address": true, "show_accuracy": true, "show_battery": true]
    @State private var active = true
    @State private var busy = false
    @State private var confirm = false
    @State private var saved = false
    @State private var error: String?
    private let labels = [("can_locate", "Neue Ortung erlauben"), ("show_history", "Verlauf freigeben"), ("show_address", "Adresse zeigen"), ("show_accuracy", "Genauigkeit zeigen"), ("show_battery", "Batterie zeigen")]
    var body: some View {
        Form {
            if share.identifier.isEmpty {
                Picker("Objekt", selection: $tracker) {
                    Text("Auswählen").tag("")
                    ForEach(Array(snapshot["catalog"].rows.enumerated()), id: \.offset) { _, item in Text(item["name"].text).tag(item["ref"].text) }
                }
                Picker("Empfänger", selection: $recipient) {
                    Text("Auswählen").tag("")
                    ForEach(snapshot["recipients"].rows, id: \.identifier) { item in Text(item["display_name"].text).tag(item.identifier) }
                }
            } else { Toggle("Freigabe aktiv", isOn: $active) }
            Section("Zugriffsrechte") {
                ForEach(labels, id: \.0) { key, label in Toggle(label, isOn: Binding(get: { permissions[key] ?? false }, set: { permissions[key] = $0; saved = false })) }
            }
            Button("Freigabe speichern") { confirm = true }.disabled(busy || (share.identifier.isEmpty && (tracker.isEmpty || recipient.isEmpty)))
            if busy { ProgressView() }
            if saved { Label("Freigabe gespeichert", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
            if let error { Text(error).foregroundStyle(.red) }
        }.disabled(busy).scrollContentBackground(.hidden).rjScreenChrome().navigationTitle("Freigaberechte").navigationBarTitleDisplayMode(.inline)
        .task { if !share.identifier.isEmpty { for (key, _) in labels { permissions[key] = share["permissions"][key].boolValue ?? false }; active = share["active"].boolValue ?? true } }
        .confirmationDialog("Diese Standortdaten und Rechte für den gewählten Benutzer freigeben?", isPresented: $confirm, titleVisibility: .visible) { Button("Speichern") { Task { await save() } } }
    }
    private func save() async {
        busy = true; defer { busy = false }; error = nil
        do {
            let path = "/api/internal-shares" + (share.identifier.isEmpty ? "" : "/\(share.identifier)")
            let payload: [String: Any] = share.identifier.isEmpty ? ["tracker_ref": tracker, "recipient_user_id": recipient, "permissions": permissions] : ["permissions": permissions, "active": active]
            _ = try await APIClient.shared.requestJSON(path: path, method: share.identifier.isEmpty ? "POST" : "PATCH", json: payload); saved = true
        } catch { self.error = error.localizedDescription }
    }
}

struct InternalShareDetail: View {
    let initial: JSONValue
    let snapshot: JSONValue
    @State private var updated: JSONValue?
    @State private var message: String?
    @State private var busy = false
    @State private var showHistory = false
    private var share: JSONValue { updated ?? initial }
    private var location: TrackerLocation? { try? JSONDecoder().decode(TrackerLocation.self, from: JSONEncoder().encode(share["tracker"]["location"])) }
    private var history: [HistoryPoint] { (try? JSONDecoder().decode([HistoryPoint].self, from: JSONEncoder().encode(share["history"]))) ?? [] }
    var body: some View {
        List {
            if let location, CLLocationCoordinate2DIsValid(location.coordinate) {
                Map { Marker(share["label"].text, coordinate: location.coordinate) }.frame(height: 240).listRowInsets(EdgeInsets())
                Text(location.address?.bestText ?? "Adresse nicht freigegeben oder nicht verfügbar")
                FreshnessLabel(timestamp: location.timestamp)
            }
            if share["available"].boolValue == false { Text(share["unavailable_reason"].text).foregroundStyle(.orange) }
            if share["permissions"]["can_locate"].boolValue == true || share["direction"].stringValue == "outgoing" {
                Button("Jetzt orten") { Task { await locate() } }.disabled(busy || share["active"].boolValue != true)
            }
            if share["permissions"]["show_history"].boolValue == true {
                Button("Freigegebenen Verlauf laden") { showHistory = true; Task { await load(history: true) } }.disabled(busy)
                if showHistory {
                    ForEach(HistoryAnalysis.filtered(history, networks: Set(history.map { ($0.network ?? "unknown").rjNormalizedProvider })).suffix(100).reversed()) { point in
                        VStack(alignment: .leading) { Text(Date(timeIntervalSince1970: TimeInterval(point.timestamp)).formatted()); Text(point.address?.bestText ?? "\(point.latitude), \(point.longitude)").font(.caption).foregroundStyle(.secondary) }
                    }
                }
            }
            if share["direction"].stringValue == "outgoing" { NavigationLink("Rechte & Aktivierung") { InternalShareEditor(snapshot: snapshot, share: share) } }
            NavigationLink("Freigabe entfernen") { ManagementForm(title: "Freigabe entfernen", path: "/api/internal-shares/\(share.identifier)", method: "DELETE", constants: ["confirmed": .bool(true)], confirmation: "Diese interne Freigabe für beide Beteiligten entfernen?", destructive: true) }
            if busy { ProgressView() }
            if let message { Text(message).foregroundStyle(.secondary) }
        }.scrollContentBackground(.hidden).rjScreenChrome().navigationTitle(share["label"].text).navigationBarTitleDisplayMode(.inline)
        .task { await load(history: false) }.refreshable { await load(history: showHistory) }
    }
    private func load(history: Bool) async {
        busy = true; defer { busy = false }
        do { let result = try await APIClient.shared.requestJSON(path: "/api/internal-shares", query: [.init(name: "history", value: history ? "1" : "0")]); updated = (result["received"].rows + result["outgoing"].rows).first { $0.identifier == initial.identifier }; if updated == nil { updated = .object(["label": initial["label"], "id": initial["id"], "available": .bool(false), "unavailable_reason": .string("Freigabe nicht mehr verfügbar.")]); message = "Freigabe nicht mehr verfügbar." } }
        catch { message = error.localizedDescription }
    }
    private func locate() async {
        busy = true; defer { busy = false }
        do { let result = try await APIClient.shared.requestJSON(path: "/api/internal-shares/\(share.identifier)/locate", method: "POST", json: [:]); message = result["message"].stringValue ?? "Ortung angefordert. Zum Abrufen später aktualisieren." } catch { message = error.localizedDescription }
    }
}

