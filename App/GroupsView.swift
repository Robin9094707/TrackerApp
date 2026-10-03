import SwiftUI

struct GroupsView: View {
    @Environment(AppModel.self) private var model
    @State private var groups: [TrackerGroup] = []
    @State private var editor: TrackerGroup?
    @State private var creating = false
    @State private var deleting: TrackerGroup?
    @State private var loading = false
    @State private var error: String?
    var body: some View {
        List {
            Section {
                Label("Ordne deine Objekte zum Beispiel nach Alltag, Familie oder Reisen.", systemImage: "folder").font(.subheadline).foregroundStyle(.secondary)
            }
            if loading { ProgressView() }
            if let error { Text(error).foregroundStyle(.red) }
            ForEach(groups) { group in
                NavigationLink { GroupObjectsView(group: group) } label: {
                    HStack(spacing: 14) {
                        Text(group.emoji ?? "📁").font(.title2)
                        VStack(alignment: .leading) {
                            Text(group.label).font(.headline)
                            Text("\(model.trackers.filter { ($0.groups ?? []).contains(group.id) }.count) sichtbare Objekte").font(.caption).foregroundStyle(.secondary)
                        }
                    }.padding(.vertical, 4)
                }
                .swipeActions {
                    Button("Löschen", role: .destructive) { deleting = group }
                    Button("Bearbeiten") { editor = group }.tint(.blue)
                }
            }
        }
        .scrollContentBackground(.hidden).rjScreenChrome().navigationTitle("Gruppen").navigationBarTitleDisplayMode(.inline)
        .toolbar { Button("Neue Gruppe", systemImage: "plus") { creating = true } }
        .task { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $creating, onDismiss: { Task { await load() } }) { NavigationStack { GroupEditorView() } }
        .sheet(item: $editor, onDismiss: { Task { await load() } }) { group in NavigationStack { GroupEditorView(group: group) } }
        .confirmationDialog("Gruppe löschen? Die Tracker bleiben erhalten.", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            if let group = deleting { Button("Gruppe löschen", role: .destructive) { Task { await remove(group) } } }
        }
    }
    private func load() async {
        loading = true; defer { loading = false }; error = nil
        do {
            let result: GroupResponse = try await APIClient.shared.request(path: "/api/v2/groups")
            groups = result.groups.sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
        } catch { self.error = error.localizedDescription }
    }
    private func remove(_ group: TrackerGroup) async {
        do {
            _ = try await APIClient.shared.requestJSON(path: "/api/v2/groups/\(group.id)", method: "DELETE")
            if model.selectedGroup == group.id { model.selectedGroup = nil }
            await model.refresh(); await load()
        } catch { self.error = error.localizedDescription }
    }
}

struct GroupObjectsView: View {
    @Environment(AppModel.self) private var model
    let group: TrackerGroup
    var body: some View {
        List {
            let trackers = model.trackers.filter { ($0.groups ?? []).contains(group.id) }
            if trackers.isEmpty { ContentUnavailableView("Noch keine Objekte", systemImage: "folder", description: Text("Wähle bei einem Objekt „Gruppen zuordnen“.")) }
            ForEach(trackers) { tracker in
                NavigationLink { TrackerDetailView(tracker: tracker) } label: { TrackerListRow(tracker: tracker) }
            }
        }.scrollContentBackground(.hidden).rjScreenChrome().navigationTitle(group.label).navigationBarTitleDisplayMode(.inline)
    }
}

struct GroupEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let group: TrackerGroup?
    @State private var label: String
    @State private var emoji: String
    @State private var busy = false
    @State private var error: String?
    init(group: TrackerGroup? = nil) {
        self.group = group; _label = State(initialValue: group?.label ?? ""); _emoji = State(initialValue: group?.emoji ?? "📁")
    }
    var body: some View {
        Form {
            Section("Gruppe") { TextField("Name", text: $label); TextField("Symbol", text: $emoji) }
            if let error { Text(error).foregroundStyle(.red) }
        }.scrollContentBackground(.hidden).rjScreenChrome().navigationTitle(group == nil ? "Neue Gruppe" : "Gruppe bearbeiten")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() }.disabled(busy) }
                ToolbarItem(placement: .confirmationAction) { Button("Sichern") { Task { await save() } }.disabled(busy || label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || label.count > 80) }
            }.interactiveDismissDisabled(busy)
    }
    private func save() async {
        busy = true; defer { busy = false }
        do {
            _ = try await APIClient.shared.requestJSON(path: group.map { "/api/v2/groups/\($0.id)" } ?? "/api/v2/groups", method: "POST", json: ["label": label.trimmingCharacters(in: .whitespacesAndNewlines), "emoji": emoji])
            await model.refresh(); dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

struct GroupAssignmentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let tracker: Tracker
    @State private var groups: [TrackerGroup] = []
    @State private var selected: Set<String>
    @State private var loaded = false
    @State private var busy = false
    @State private var error: String?
    init(tracker: Tracker) { self.tracker = tracker; _selected = State(initialValue: Set(tracker.groups ?? [])) }
    var body: some View {
        Form {
            ForEach(groups) { group in
                Toggle("\(group.emoji ?? "📁") \(group.label)", isOn: Binding(get: { selected.contains(group.id) }, set: { value in
                    if value { selected.insert(group.id) } else { selected.remove(group.id) }
                }))
            }
            if loaded && groups.isEmpty { Text("Lege zuerst unter Ich → Gruppen eine Gruppe an.").foregroundStyle(.secondary) }
            if let error { Text(error).foregroundStyle(.red) }
        }.scrollContentBackground(.hidden).rjScreenChrome().navigationTitle("Gruppen zuordnen")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() }.disabled(busy) }
                ToolbarItem(placement: .confirmationAction) { Button("Sichern") { Task { await save() } }.disabled(!loaded || busy || selected.count > 20) }
            }
            .task {
                do { let result: GroupResponse = try await APIClient.shared.request(path: "/api/v2/groups"); groups = result.groups; loaded = true }
                catch { self.error = error.localizedDescription }
            }
    }
    private func save() async {
        busy = true; defer { busy = false }
        do {
            _ = try await APIClient.shared.requestJSON(path: "/api/v2/trackers/\(tracker.provider)/\(tracker.apiID)/preferences", method: "POST", json: ["groups": selected.sorted()])
            await model.refresh(); dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

