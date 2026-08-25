import SwiftUI
import UIKit

enum RJDesign {
    static let corner: CGFloat = 24
    static let compactCorner: CGFloat = 17
}

extension View {
    @ViewBuilder
    func rjGlass<S: Shape>(in shape: S) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
        }
    }

    func rjCard() -> some View {
        padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .rjGlass(in: RoundedRectangle(cornerRadius: RJDesign.corner, style: .continuous))
    }
}

struct ProviderBadge: View {
    let provider: String
    var body: some View {
        Label(provider.capitalized, systemImage: symbol)
            .font(.caption.weight(.semibold)).padding(.horizontal, 9).padding(.vertical, 5)
            .background(.secondary.opacity(0.12), in: Capsule())
            .accessibilityLabel("Netzwerk \(provider)")
    }
    private var symbol: String {
        switch provider.lowercased() {
        case "apple": "apple.logo"
        case "google": "g.circle.fill"
        case "samsung": "s.circle.fill"
        case "fusion": "point.3.connected.trianglepath.dotted"
        default: "dot.radiowaves.left.and.right"
        }
    }
}

enum Haptics {
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
    static func impact() { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
}

extension Date {
    static func fromUnix(_ value: Int?) -> Date? { value.map { Date(timeIntervalSince1970: TimeInterval($0)) } }
}

extension Double {
    var metersText: String {
        if self >= 1000 { return String(format: "%.1f km", self / 1000) }
        return "\(Int(self.rounded())) m"
    }
}
