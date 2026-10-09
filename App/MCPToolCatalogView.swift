import SwiftUI

struct MCPToolCatalogView: View {
    @State private var tools: [JSONValue] = []
    @State private var search = ""
    @State private var error: String?
    var body: some View {
        List {
            Section {
                Label("\(tools.count) Werkzeuge", systemImage: "square.grid.2x2.fill").font(.headline)
                Text("Der Katalog zeigt die Tools für deinen Besitzerzugang. Freigabe-Verbindungen erhalten einen getrennten, eingeschränkten Katalog.").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(tools.filter { search.isEmpty || $0["name"].text.localizedCaseInsensitiveContains(search) || $0["description"].text.localizedCaseInsensitiveContains(search) }, id: \.toolName) { tool in
                DisclosureGroup {
                    Text(tool["description"].text).font(.subheadline)
                    Text(tool["name"].text).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    LabeledContent("Bestätigung nötig", value: tool["annotations"]["readOnlyHint"].boolValue == true ? "Nein" : "Ja")
                    ForEach((tool["inputSchema"]["properties"].objectValue ?? [:]).keys.sorted(), id: \.self) { key in
                        let field = tool["inputSchema"]["properties"][key]
                        VStack(alignment: .leading, spacing: 3) {
                            Text(key + (tool["inputSchema"]["required"].rows.contains(.string(key)) ? " *" : "")).font(.caption.bold())
                            Text(field["description"].stringValue ?? field["type"].text).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                } label: {
                    Label(tool["title"].stringValue ?? tool["name"].text,
                          systemImage: tool["annotations"]["readOnlyHint"].boolValue == true ? "eye" : "slider.horizontal.3")
                }
            }
            if let error { Text(error).foregroundStyle(.red) }
        }.rjListChrome().navigationTitle("ChatGPT-Tools").searchable(text: $search)
            .task { await load() }.refreshable { await load() }
    }
    private func load() async {
        do { tools = try await APIClient.shared.requestJSON(path: "/api/mcp/tools")["tools"].rows; error = nil }
        catch { self.error = error.localizedDescription }
    }
}

private extension JSONValue { var toolName: String { self["name"].text } }
