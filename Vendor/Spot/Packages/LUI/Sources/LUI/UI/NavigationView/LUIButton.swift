//
//  LUIButton.swift
//  LUIExample
//
//  Created by Leon Böttger on 21.08.23.
//

import SwiftUI

public struct LUIButton<Content: View>: View {
    public init(action: @escaping () -> Void, @ViewBuilder label: () -> Content) {
        self.action = action
        self.label = label()
    }

    let action: () -> Void
    let label: Content

    public var body: some View {
        Button(
            action: action,
            label: {
                label
                    .contentShape(Rectangle())
            }
        )
        .buttonStyle(LUIButtonStyle())
    }
}

public struct LUIButtonStyle: ButtonStyle {
    public init() {}

    @Environment(\.accessibilityShowButtonShapes)
    private var accessibilityShowButtonShapes

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.5 : 1)
    }
}
