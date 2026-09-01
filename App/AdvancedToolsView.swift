import SwiftUI

struct AdvancedToolsView: View {
    @State private var routes: [APIRoute] = []
    @State private var selectedPath = "/api/state"
    @State private var method = "GET"
    @State private var requestBody = "{}"
    @State private var output = ""
    @State private var searching = ""
    @State private var running = false

    var filtered: [APIRoute] {
        routes.filter {
            searching.isEmpty ||
            $0.path.localizedCaseInsensitiveContains(searching) ||
            $0.endpoint.localizedCaseInsensitiveContains(searching)
        }
    }

    var body: some View {
        List {
            Section("Native API-Konsole") {
                TextField("API-Pfad", text: $selectedPath)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                Picker("Methode", selection: $method) {
                    ForEach(["GET", "POST", "PATCH", "DELETE"], id: \.self) { Text($0) }
                }
                .pickerStyle(.segmented)

                if method != "GET" {
                    TextEditor(text: $requestBody)
                        .font(.system(.caption, design: .monospaced))
                        .frame(minHeight: 130)
                        .padding(8)
                        .rjGlass(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                Button { Task { await run() } } label: {
                    HStack(spacing: 8) {
                        if running { ProgressView().controlSize(.small) }
                        else { Image(systemName: "play.fill") }
                        Text(running ? "Läuft …" : "Request ausführen")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .rjGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(running || selectedPath.isEmpty)

                if !output.isEmpty {
                    ScrollView(.horizontal) {
                        Text(output)
                            .font(.system(.caption2, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 320)
                }
            }
            .listRowBackground(Color.clear)

            Section("Alle Server-APIs (\(routes.count))") {
                TextField("Filtern", text: $searching)
                ForEach(filtered.prefix(300)) { route in
                    Button {
                        selectedPath = route.path
                        method = route.methods.first ?? "GET"
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(route.methods.joined(separator: ", "))
                                    .font(.caption.bold())
                                    .foregroundStyle(.tint)
                                if route.mobileNative == true {
                                    Text("NATIV")
                                        .font(.caption2.bold())
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(.tint.opacity(0.12), in: Capsule())
                                }
                            }
                            Text(route.path)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.primary)
                            Text(route.endpoint)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 3)
                    }
                    .buttonStyle(.plain)
                }
            }
            .listRowBackground(Color.clear)
        }
        .rjListChrome()
        .navigationTitle("API-Werkzeuge")
        .task { await loadRoutes() }
    }

    private func loadRoutes() async {
        do { routes = try await APIClient.shared.capabilities().allApiRoutes ?? [] }
        catch { output = error.localizedDescription }
    }

    private func run() async {
        running = true
        defer { running = false }
        do {
            output = try await APIClient.shared.requestRaw(
                path: selectedPath,
                method: method,
                bodyText: method == "GET" ? "" : requestBody
            )
        } catch {
            output = "Fehler: \(error.localizedDescription)"
        }
    }
}
