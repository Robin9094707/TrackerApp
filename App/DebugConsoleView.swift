import SwiftUI

struct DebugConsoleView: View {
    @State private var logger = DebugLogger.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if logger.entries.isEmpty {
                    ContentUnavailableView("Kein Debug-Protokoll", systemImage: "ladybug")
                        .frame(maxWidth: .infinity, minHeight: 260)
                } else {
                    ForEach(Array(logger.entries.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(.caption2, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(16)
            .rjCard()
            .padding(16)
        }
        .rjScreenChrome()
        .navigationTitle("Debug")
        .toolbar {
            Button("Leeren") { logger.clear() }
        }
    }
}
