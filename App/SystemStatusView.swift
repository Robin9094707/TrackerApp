import SwiftUI

struct SystemStatusView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        List {
            Section("Server") { LabeledContent("Name", value: model.bootstrap?.api?.serverName ?? "Universal Tag Studio"); LabeledContent("Version", value: model.bootstrap?.api?.serverVersion ?? "–"); LabeledContent("Mobile API", value: model.bootstrap?.api?.version ?? "1.0"); if let date = model.lastRefresh { LabeledContent("Synchronisiert") { Text(date, style: .relative) } } }
            Section("Push") { LabeledContent("APNs", value: model.bootstrap?.push?.serverConfigured == true ? "Bereit" : "Optional einzurichten"); LabeledContent("iPhones", value: "\(model.bootstrap?.push?.activeDevices ?? 0)") }
            if let providers = model.bootstrap?.providers { Section("Provider Health") { Text(providers.prettyPrinted).font(.system(.caption, design: .monospaced)).textSelection(.enabled) } }
            if let polling = model.bootstrap?.polling { Section("Polling") { Text(polling.prettyPrinted).font(.system(.caption, design: .monospaced)).textSelection(.enabled) } }
        }.navigationTitle("Systemstatus")
    }
}
