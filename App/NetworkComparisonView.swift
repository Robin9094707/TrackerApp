import SwiftUI

struct NetworkComparisonView: View {
    @State private var tests: [JSONValue] = []
    @State private var error: String?
    var body: some View {
        List {
            NavigationLink("Neuen Vergleich starten") { ComparisonCreateView() }
            ForEach(tests, id: \.identifier) { test in
                NavigationLink { ComparisonDetailView(id: test.identifier) } label: {
                    VStack(alignment: .leading, spacing: 4) { Text(test["name"].text).font(.headline); Text(test["status"].stringValue == "running" ? "Läuft" : "Beendet").font(.caption).foregroundStyle(.secondary) }
                }
            }
            if tests.isEmpty && error == nil { Text("Noch keine Vergleichstests").foregroundStyle(.secondary) }
            if let error { Text(error).foregroundStyle(.red) }
        }.navigationTitle("Netzwerkvergleich").navigationBarTitleDisplayMode(.inline)
        .task { await load() }.refreshable { await load() }
    }
    private func load() async { do { tests = try await APIClient.shared.requestJSON(path: "/api/comparison-tests")["tests"].rows; error = nil } catch { self.error = error.localizedDescription } }
}
struct ComparisonCreateView: View {
    @Environment(AppModel.self) private var model
    @State private var selected: Set<String> = []
    @State private var name = ""
    var body: some View {
        Form {
            TextField("Name des Vergleichs", text: $name)
            Section("Objekte oder Fusion auswählen") {
                ForEach(model.trackers) { tracker in
                    Toggle(tracker.name, isOn: Binding(get: { selected.contains(tracker.ref) }, set: { if $0 { selected.insert(tracker.ref) } else { selected.remove(tracker.ref) } }))
                }
            }
            Text("Eine Fusion wird in ihre Ortungsquellen aufgeteilt. Der Server prüft die Auswahl und verhindert Überschneidungen mit laufenden Tests.").font(.caption).foregroundStyle(.secondary)
            NavigationLink("Auswahl prüfen & starten") {
                ManagementForm(title: "Vergleich starten", path: "/api/comparison-tests", constants: ["name": .string(name), "trackers": .array(selected.sorted().map(JSONValue.string)), "confirmed": .bool(true)], explanation: "\(selected.count) ausgewählte Objekte. Der Test zeichnet neue Meldungen auf, bis du ihn beendest.", confirmation: "Diesen Netzwerkvergleich starten?")
            }.disabled(selected.isEmpty)
        }.navigationTitle("Neuer Vergleich").navigationBarTitleDisplayMode(.inline)
    }
}
struct ComparisonDetailView: View {
    let id: String
    @State private var test: JSONValue = .null
    @State private var message: String?
    @State private var busy = false
    var body: some View {
        List {
            Section("Vergleich") { Text(test["name"].text).font(.headline); LabeledContent("Status", value: test["status"].text) }
            Section("Meldungen je Quelle") {
                ForEach((test["report_counts"].objectValue ?? [:]).keys.sorted(), id: \.self) { ref in
                    LabeledContent(ref, value: test["report_counts"][ref].text)
                }
            }
            if test["status"].stringValue == "running" {
                Button("Neue Meldungen anfordern") { Task { await refreshSources() } }.disabled(busy)
                NavigationLink("Beenden & auswerten") { ManagementForm(title: "Vergleich beenden", path: "/api/comparison-tests/\(id)/finish", constants: ["confirmed": .bool(true)], confirmation: "Aufzeichnung beenden und Ergebnisse berechnen?") }
            }
            Section("Auswertung") { ManagementRows(value: test["results"]) }
            NavigationLink("Test löschen") { ManagementForm(title: "Vergleich löschen", path: "/api/comparison-tests/\(id)", method: "DELETE", constants: ["confirmed": .bool(true)], confirmation: "Vergleich inklusive aufgezeichneter Testergebnisse löschen?", destructive: true) }
            if busy { ProgressView() }
            if let message { Text(message).foregroundStyle(.secondary) }
        }.navigationTitle("Vergleichsergebnis").navigationBarTitleDisplayMode(.inline)
        .task { await load() }.refreshable { await load() }
    }
    private func load() async { do { test = try await APIClient.shared.requestJSON(path: "/api/comparison-tests/\(id)")["test"] } catch { message = error.localizedDescription } }
    private func refreshSources() async {
        busy = true; defer { busy = false }
        do { _ = try await APIClient.shared.requestJSON(path: "/api/comparison-tests/\(id)/refresh", method: "POST", json: [:]); message = "Abrufe angefordert. Ergebnisse mit Ziehen aktualisieren." } catch { message = error.localizedDescription }
    }
}
