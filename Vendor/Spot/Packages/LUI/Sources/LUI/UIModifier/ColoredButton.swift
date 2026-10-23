//
//  ColoredButton.swift
//
//
//  Created by Leon Böttger on 29.07.23.
//

import SwiftUI

public struct ColoredButton: View {
    public init(
        label: String,
        color: [Color] = luiModel.configuration.defaultColors,
        loading: Bool = false,
        imageName: String = "chevron.right",
        action: @escaping () -> Void
    ) {
        self.label = label
        self.color = color
        self.action = action
        self.imageName = imageName
        self.loading = loading
    }

    let label: String
    let imageName: String
    let loading: Bool
    let color: [Color]
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled: Bool

    public var body: some View {
        LUIButton(action: {
            lightVibration()

            action()

        }) {
            HStack {
                Text(label.localized())
                    .lineLimit(1)
                    .rounded()

                if loading {
                    LoadingIndicator(color: .white)
                        .padding(.leading, 2)
                        .frame(width: 25, height: 16)
                } else {
                    Image(systemName: imageName)
                }
            }
            .coloredButton(colors: color)
        }
        .padding(.horizontal)
        .opacity(isEnabled ? 1 : 0.5)
        .animation(.easeInOut, value: loading)
    }
}

extension View {
    func coloredButton(colors: [Color]) -> ModifiedContent<Self, ColoredButtonModifier> {
        modifier(ColoredButtonModifier(colors: colors))
    }
}

struct ColoredButtonModifier: ViewModifier {
    let colors: [Color]

    func body(content: Content) -> some View {
        content
            .foregroundColor(.white)
            .font(.headline)
            .padding()
            .padding(.horizontal, 10)
            .padding(.vertical, -1)
            .background(
                ZStack {
                    getGradient(colors: colors)
                    LinearGradient(
                        colors: [.clear, .white.opacity(0.2)], startPoint: .bottom, endPoint: .top
                    )
                }
                .cornerRadius(luiModel.cornerRadius)
            )
    }
}
