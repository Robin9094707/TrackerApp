import SwiftUI
import UniformTypeIdentifiers

struct AdvancedToolsView: View {
    @State private var routes: [APIRoute] = []
    @State private var selectedPath = "/api/state"
    @State private var method = "GET"
    @State private var requestBody = "{}"
    @State private var output = ""
    @State private var searching = ""
    @State private var running = false
    @State private var parameters: [String: String] = [:]
    @State private var parameterNames: [String] = []
    @State private var encoding = "JSON"
    @State private var confirm = false
    @State private var importing = false
    @State private var upload: Data?
    @State private var fileName = "upload.json"
    @State private var fileField = "file"
    @State private var resultFile: URL?
    @State private var selectedRoute: APIRoute?

    private var resolvedPath: String {
        var result = selectedPath
        for name in parameterNames {
            let value = (parameters[name] ?? "").addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
            let pattern = "<(?:(?:[^<>:]+):)?" + NSRegularExpression.escapedPattern(for: name) + ">"
            if let regex = try? NSRegularExpression(pattern: pattern) {
                result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: NSRegularExpression.escapedTemplate(for: value))
            }
        }
        return result
    }

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
                ForEach(parameterNames, id: \.self) { name in
                    TextField(name, text: Binding(get: { parameters[name] ?? "" }, set: { parameters[name] = $0 }))
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                Text("Query-Parameter direkt an den Pfad anhängen, z. B. ?ref=apple%3ASchluessel. Serverrechte und Validierung gelten für jede Aktion.")
                    .font(.caption).foregroundStyle(.secondary)

                Picker("Methode", selection: $method) {
                    ForEach(["GET", "POST", "PUT", "PATCH", "DELETE"], id: \.self) { Text($0) }
                }
                .pickerStyle(.segmented)

                if method != "GET" {
                    Picker("Übertragung", selection: $encoding) { ForEach(["JSON", "Formular", "Datei"], id: \.self) { Text($0) } }
                    if encoding == "Datei" {
                        TextField("Dateifeld", text: $fileField).textInputAutocapitalization(.never)
                        Button(upload == nil ? "Datei auswählen" : fileName, systemImage: "doc.badge.plus") { importing = true }
                    }
                    TextEditor(text: $requestBody)
                        .font(.system(.caption, design: .monospaced))
                        .frame(minHeight: 130)
                        .padding(8)
                        .rjGlass(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                Button { if method == "GET" { Task { await run() } } else { confirm = true } } label: {
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
                .disabled(running || selectedPath.isEmpty || parameterNames.contains { (parameters[$0] ?? "").isEmpty })
                if let resultFile { ShareLink(item: resultFile) { Label("Antwortdatei sichern", systemImage: "square.and.arrow.up") } }

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
                ForEach(filtered) { route in
                    Button {
                        selectedPath = route.path
                        selectedRoute = route
                        parameterNames = route.arguments ?? []; parameters = [:]
                        method = route.methods.contains("GET") ? "GET" : (route.methods.first ?? "POST")
                        requestBody = "{}"; output = ""; resultFile = nil
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
        .refreshable { await loadRoutes() }
        .confirmationDialog("Serveraktion ausführen?", isPresented: $confirm, titleVisibility: .visible) {
            Button("\(method) ausführen", role: method == "DELETE" ? .destructive : nil) { Task { await run() } }
        } message: { Text("\(method) \(resolvedPath)\nDie angegebenen Daten werden an deinen Server gesendet.") }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.data]) { result in
            do {
                let url = try result.get(); let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= 20 * 1024 * 1024 else { throw APIError.message("Maximal 20 MB pro Datei.") }
                upload = try Data(contentsOf: url); fileName = url.lastPathComponent
            } catch { output = error.localizedDescription }
        }
    }

    private func loadRoutes() async {
        do { routes = try await APIClient.shared.capabilities().allApiRoutes ?? [] }
        catch { output = error.localizedDescription }
    }

    private func run() async {
        running = true
        defer { running = false }
        do {
            if let selectedRoute, !selectedRoute.methods.contains(method) { throw APIError.message("Diese Methode ist für den gewählten Endpunkt nicht verfügbar.") }
            let result = try await APIClient.shared.requestAdvanced(path: resolvedPath, method: method,
                bodyText: method == "GET" ? "{}" : requestBody, encoding: encoding,
                fileData: upload, fileName: fileName, fileField: fileField)
            output = result.0; resultFile = result.1
        } catch {
            output = "Fehler: \(error.localizedDescription)"
        }
    }
}
