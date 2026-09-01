import SwiftUI

struct SystemStatusView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                serverCard
                pushCard
                if let providers = model.bootstrap?.providers { jsonCard(title: "Provider Health", symbol: "antenna.radiowaves.left.and.right", value: providers.prettyPrinted) }
                if let polling = model.bootstrap?.polling { jsonCard(title: "Polling", symbol: "arrow.triangle.2.circlepath", value: polling.prettyPrinted) }
            }
            .padding(16)
            .padding(.bottom, 28)
        }
        .rjScreenChrome()
        .navigationTitle("Systemstatus")
        .navigationBarTitleDisplayMode(.large)
        .refreshable { await model.refresh() }
    }

    private var serverCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                RJSectionTitle(title: "Server", subtitle: model.bootstrap?.api?.serverName ?? "Universal Tag Studio", symbol: "server.rack")
                Spacer()
                RJStatusPill(text: "Online", symbol: "checkmark.circle.fill", tint: .green)
            }
            Divider()
            LabeledContent("Name", value: model.bootstrap?.api?.serverName ?? "Universal Tag Studio")
            LabeledContent("Version", value: model.bootstrap?.api?.serverVersion ?? "–")
            LabeledContent("Mobile API", value: model.bootstrap?.api?.version ?? "1.0")
            if let date = model.lastRefresh { LabeledContent("Synchronisiert") { Text(date.rjTimelineText) } }
        }
        .rjCard()
    }

    private var pushCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            RJSectionTitle(title: "Push", subtitle: "Native iPhone-Benachrichtigungen", symbol: "bell.badge.fill")
            Divider()
            LabeledContent("APNs", value: model.bootstrap?.push?.serverConfigured == true ? "Bereit" : "Optional einzurichten")
            LabeledContent("iPhones", value: "\(model.bootstrap?.push?.activeDevices ?? 0)")
        }
        .rjCard()
    }

    private func jsonCard(title: String, symbol: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            RJSectionTitle(title: title, symbol: symbol)
            Divider()
            ScrollView(.horizontal) {
                Text(value)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .rjCard()
    }
}
