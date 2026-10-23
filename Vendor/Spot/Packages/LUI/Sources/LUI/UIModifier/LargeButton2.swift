//
//  LargeButton2.swift
//
//
//  Created by Leon Böttger on 16.03.24.
//

import SwiftUI

public struct LargeButton2: View {
    public init(
        label: String,
        lighter: Bool = false,
        loading: Bool = false,
        action: @escaping () -> Void
    ) {
        self.label = label
        self.lighter = lighter
        self.action = action
        self.loading = loading
    }

    let label: String
    let lighter: Bool
    let loading: Bool
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled: Bool

    public var body: some View {
        LUIButton(action: {
            lightVibration()

            action()

        }) {
            HStack(spacing: 0) {
                Text(label.localized())
                    .lineLimit(1)
                    .rounded()
                    .padding(.vertical, 0)
                    .padding(.leading, 0)

                if loading {
                    LoadingIndicator()
                        .frame(width: 18)
                        .padding(.leading, 10)
                }
            }
            .largeButton2(lighter: lighter)
        }
        .padding(.horizontal, 15)
        .opacity(isEnabled ? 1 : 0.5)
    }
}

extension View {
    func largeButton2(lighter: Bool) -> ModifiedContent<Self, LargeButtonModifier2> {
        modifier(LargeButtonModifier2(lighter: lighter))
    }
}

struct LargeButtonModifier2: ViewModifier {
    let lighter: Bool
    @Environment(\.colorScheme) var colorScheme

    func body(content: Content) -> some View {
        content
            .foregroundColor(colorScheme.isLight ? .mainColor : .white)
            .font(.headline)
            .padding(.vertical, 0)
            .padding()
            .padding(.vertical, -1)
            .frame(minWidth: 0, maxWidth: 300, alignment: .center)
            .background(
                ZStack {
                    if colorScheme.isLight {
                        Color.sheetBackgroundColor
                        Color.gray.opacity(0.2)
                    } else {
                        Color.sheetForegroundColor

                        if lighter {
                            Color.white.opacity(0.08)
                        }
                    }
                }
                .cornerRadius(luiModel.cornerRadius * 0.8)
            )
    }
}
