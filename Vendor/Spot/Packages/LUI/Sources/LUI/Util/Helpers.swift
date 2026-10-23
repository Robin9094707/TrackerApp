//
//  Helpers.swift
//
//
//  Created by Leon Böttger on 30.07.23.
//

import SwiftUI

public extension Color {
    static let mainColor = Color("MainColor", bundle: .module)
    static let grayColor = mainColor.opacity(0.6)

    static let sheetForegroundColor = Color("SheetForegroundColor", bundle: .module)
    static let sheetBackgroundColor = Color("SheetBackgroundColor", bundle: .module)

    static let defaultForegroundColor = Color("DefaultForegroundColor", bundle: .module)
    static let defaultBackgroundColor = Color("DefaultBackgroundColor", bundle: .module)
}

public extension ColorScheme {
    var isLight: Bool {
        self == ColorScheme.light
    }

    var isDark: Bool {
        self == ColorScheme.dark
    }
}

public extension String {
    func localized() -> String {
        NSLocalizedString(self, comment: "")
    }
}

extension String {
    func liblocalized() -> String {
        NSLocalizedString(self, bundle: Bundle.module, comment: "")
    }
}

struct SafeAreaInsetsKey: EnvironmentKey {
    static var defaultValue: EdgeInsets {
        UIApplication.shared.myKeyWindow?.safeAreaInsets.swiftUiInsets ?? EdgeInsets()
    }
}

private extension UIEdgeInsets {
    var swiftUiInsets: EdgeInsets {
        EdgeInsets(top: top, leading: left, bottom: bottom, trailing: right)
    }
}

public extension EnvironmentValues {
    var safeAreaInsets: EdgeInsets {
        self[SafeAreaInsetsKey.self]
    }
}

public func isiPadOrMac() -> Bool {
    let device = UIDevice.current

    return device.model == "iPad"
}

public func getOSName() -> String {
    UIDevice.current.systemName
}

public extension View {
    @ViewBuilder func `if`(_ condition: Bool, transform: (Self) -> some View)
        -> some View
    {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

public extension AnyTransition {
    static var blur: AnyTransition {
        AnyTransition.modifier(
            active: BlurModifier(percent: 1, radius: 5), identity: BlurModifier(percent: 0, radius: 5)
        ).combined(with: .opacity)
    }
}

struct BlurModifier: ViewModifier {
    let percent: Double
    let radius: Double

    func body(content: Content) -> some View {
        content.blur(radius: percent * radius)
    }
}

/// Opens an url. Quits app.
public func openURL(url: URL) {
    UIApplication.shared.open(url, options: [:], completionHandler: nil)
}

/// Centers the text and reduces opacity
struct TextCenterModifier: ViewModifier {
    @Environment(\.colorScheme) var colorScheme

    func body(content: Content) -> some View {
        content
            .multilineTextAlignment(.center)
    }
}

/// Reduces opacity
struct OpacityModifier: ViewModifier {
    @Environment(\.colorScheme) var colorScheme
    let darkModeAsWell: Bool

    func body(content: Content) -> some View {
        content
            .opacity(colorScheme.isLight || darkModeAsWell ? 0.7 : 1)
    }
}

extension View {
    /// Centers the text and reduces opacity
    func centered() -> some View {
        modifier(TextCenterModifier())
    }

    /// Reduces opacity
    func lowerOpacity(darkModeAsWell: Bool = false) -> some View {
        modifier(OpacityModifier(darkModeAsWell: darkModeAsWell))
    }
}

/// Returns true if current device is simulator
public func isSimulator() -> Bool {
    #if targetEnvironment(simulator)
        return true
    #else
        return false
    #endif
}

public func ?? <T>(lhs: Binding<T?>, rhs: T) -> Binding<T> {
    Binding(
        get: { lhs.wrappedValue ?? rhs },
        set: { lhs.wrappedValue = $0 }
    )
}

public func runAfter(seconds: Double, _ action: @escaping () -> Void) {
    DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
        action()
    }
}

func getGradient(colors: [Color]) -> LinearGradient {
    LinearGradient(
        gradient: .init(colors: colors), startPoint: .bottomLeading, endPoint: .topTrailing
    )
}
