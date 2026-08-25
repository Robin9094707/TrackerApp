import SwiftUI

struct DebugConsoleView: View {
    @State private var logger = DebugLogger.shared
    var body: some View {
        List { ForEach(Array(logger.entries.enumerated()), id: \.offset) { _, line in Text(line).font(.system(.caption2, design: .monospaced)).textSelection(.enabled) } }
            .navigationTitle("Debug").toolbar { Button("Leeren") { logger.clear() } }
    }
}
