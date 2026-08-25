import SwiftUI

struct AdvancedToolsView: View {
    @State private var routes: [APIRoute] = []
    @State private var selectedPath = "/api/state"
    @State private var method = "GET"
    @State private var body = "{}"
    @State private var output = ""
    @State private var searching = ""
    @State private var running = false

    var filtered: [APIRoute] { routes.filter { searching.isEmpty || $0.path.localizedCaseInsensitiveContains(searching) || $0.endpoint.localizedCaseInsensitiveContains(searching) } }

    var body: some View {
        List {
            Section("Native API-Konsole") {
                TextField("API-Pfad", text: $selectedPath).textInputAutocapitalization(.never).autocorrectionDisabled()
                Picker("Methode", selection: $method) { ForEach(["GET", "POST", "PATCH", "DELETE"], id: \.self) { Text($0) } }.pickerStyle(.segmented)
                if method != "GET" { TextEditor(text: $body).font(.system(.caption, design: .monospaced)).frame(minHeight: 130).overlay(RoundedRectangle(cornerRadius: 10).stroke(.secondary.opacity(0.2))) }
                Button { Task { await run() } } label: { Label(running ? "Läuft …" : "Request ausführen", systemImage: "play.fill") }.disabled(running || selectedPath.isEmpty)
                if !output.isEmpty { ScrollView(.horizontal) { Text(output).font(.system(.caption2, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 320) }
            }
            Section("Alle Server-APIs (\(routes.count))") {
                TextField("Filtern", text: $searching)
                ForEach(filtered.prefix(300)) { route in
                    Button { selectedPath = route.path; method = route.methods.first ?? "GET" } label: {
                        VStack(alignment: .leading, spacing: 4) { HStack { Text(route.methods.joined(separator: ", ")).font(.caption.bold()).foregroundStyle(.tint); if route.mobileNative == true { Text("NATIV").font(.caption2.bold()).padding(.horizontal, 5).background(.tint.opacity(0.12), in: Capsule()) } }; Text(route.path).font(.system(.caption, design: .monospaced)).foregroundStyle(.primary); Text(route.endpoint).font(.caption2).foregroundStyle(.secondary) }
                    }.buttonStyle(.plain)
                }
            }
        }.navigationTitle("API-Werkzeuge").task { await loadRoutes() }
    }

    private func loadRoutes() async { do { routes = try await APIClient.shared.capabilities().allApiRoutes ?? [] } catch { output = error.localizedDescription } }
    private func run() async { running = true; defer { running = false }; do { output = try await APIClient.shared.requestRaw(path: selectedPath, method: method, bodyText: method == "GET" ? "" : body) } catch { output = "Fehler: \(error.localizedDescription)" } }
}
