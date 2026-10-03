import SwiftUI

extension JSONValue {
    var text: String {
        switch self { case .string(let s): s; case .number(let n): n == n.rounded() ? String(format: "%.0f", n) : String(n); case .bool(let b): b ? "Ja" : "Nein"; default: "–" }
    }
    var foundationValue: Any {
        switch self {
        case .string(let s): return s
        case .number(let n): return n
        case .bool(let b): return b
        case .array(let a): return a.map(\.foundationValue)
        case .object(let o): return o.mapValues(\.foundationValue)
        case .null: return NSNull()
        }
    }
    var rows: [JSONValue] { arrayValue }
    var identifier: String { self["id"].stringValue ?? self["name"].stringValue ?? "" }
}

struct ManagementField: Identifiable {
    enum Kind: Equatable { case text, secret, toggle }
    let id: String
    let label: String
    var kind: Kind = .text
    var required = false
    var minimum = 0
}

/// Native, labelled forms; mutations only start after the user submits and confirms.
struct ManagementForm: View {
    let title: String
    let path: String
    var method = "POST"
    let fields: [ManagementField]
    var constants: [String: JSONValue] = [:]
    var explanation = ""
    var confirmation = "Änderungen auf dem Server speichern?"
    var destructive = false
    var onSuccess: ((JSONValue) -> Void)?
    @State private var values: [String: JSONValue]
    @State private var busy = false
    @State private var error: String?
    @State private var result: JSONValue?
    @State private var confirm = false
    init(title: String, path: String, method: String = "POST", fields: [ManagementField] = [], initial: [String: JSONValue] = [:], constants: [String: JSONValue] = [:], explanation: String = "", confirmation: String = "Änderungen auf dem Server speichern?", destructive: Bool = false, onSuccess: ((JSONValue) -> Void)? = nil) {
        self.title = title; self.path = path; self.method = method; self.fields = fields; self.constants = constants
        self.explanation = explanation; self.confirmation = confirmation; self.destructive = destructive; self.onSuccess = onSuccess
        _values = State(initialValue: initial)
    }
    private var valid: Bool {
        if path == "/api/security/password", values["new_password"]?.stringValue != values["confirm_password"]?.stringValue { return false }
        return fields.allSatisfy { f in
            if f.kind == .toggle { return true }
            let s = values[f.id]?.stringValue ?? ""
            return (!f.required || !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) && (s.isEmpty || s.count >= f.minimum)
        }
    }
    var body: some View {
        Form {
            if !explanation.isEmpty { Section { Text(explanation).foregroundStyle(.secondary) } }
            if result == nil {
                Section {
                    ForEach(fields) { field in
                        switch field.kind {
                        case .toggle: Toggle(field.label, isOn: Binding(get: { values[field.id]?.boolValue ?? false }, set: { values[field.id] = .bool($0) }))
                        case .secret: SecureField(field.label, text: string(field.id)).textContentType(.password)
                        case .text: TextField(field.label, text: string(field.id)).textInputAutocapitalization(.never).autocorrectionDisabled()
                        }
                    }
                }
                Button(title, role: destructive ? .destructive : nil) { confirm = true }.disabled(!valid || busy)
            } else {
                Label("Erfolgreich ausgeführt", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                if let message = result?["message"].stringValue { Text(message) }
                if let backup = result?["pre_restore_backup"].stringValue { LabeledContent("Sicherung vor Wiederherstellung", value: backup) }
            }
            if busy { ProgressView("Wird ausgeführt …") }
            if let error { Text(error).foregroundStyle(.red) }
        }
        .disabled(busy).scrollContentBackground(.hidden).rjScreenChrome().navigationTitle(title).navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(confirmation, isPresented: $confirm, titleVisibility: .visible) {
            Button(title, role: destructive ? .destructive : nil) { Task { await submit() } }
        }
    }
    private func string(_ key: String) -> Binding<String> {
        Binding(get: { values[key]?.stringValue ?? "" }, set: { values[key] = .string($0) })
    }
    private func submit() async {
        guard !busy else { return }; busy = true; error = nil; defer { busy = false }
        do {
            var payload = values
            for field in fields where field.kind == .toggle && payload[field.id] == nil { payload[field.id] = .bool(false) }
            for (key, value) in constants { payload[key] = value }
            let response = try await APIClient.shared.requestJSON(path: path, method: method, json: payload.mapValues(\.foundationValue))
            result = response
            for field in fields where field.kind == .secret { values[field.id] = nil }
            onSuccess?(response)
        } catch { self.error = error.localizedDescription }
    }
}

struct ManagementRows: View {
    let value: JSONValue
    var body: some View {
        ForEach((value.objectValue ?? [:]).keys.sorted(), id: \.self) { key in
            let child = value[key]
            if child.objectValue != nil || !child.rows.isEmpty {
                DisclosureGroup(key.replacingOccurrences(of: "_", with: " ").capitalized) {
                    if child.objectValue != nil { ManagementRows(value: child) }
                    else { ForEach(Array(child.rows.enumerated()), id: \.offset) { _, row in
                        if row.objectValue != nil { ManagementRows(value: row) } else { Text(row.text) }
                    } }
                }
            } else { LabeledContent(key.replacingOccurrences(of: "_", with: " ").capitalized, value: child.text) }
        }
    }
}

