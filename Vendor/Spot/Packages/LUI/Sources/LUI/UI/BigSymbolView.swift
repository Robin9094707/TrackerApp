//
//  BigSymbolView.swift
//
//
//  Created by Leon Böttger on 03.08.23.
//

import SwiftUI

public struct BigSymbolViewWithText<V1: View>: View {
    public init(
        symbol: String, subtitle: String, title: String = "",
        @ViewBuilder bottomView: @escaping () -> V1
    ) {
        self.symbol = symbol
        self.subtitle = subtitle
        self.title = title
        self.bottomView = bottomView
    }

    let bottomView: () -> V1
    let symbol: String
    let subtitle: String
    let title: String

    public var body: some View {
        BigSymbolView(
            symbol: symbol, title: title,
            textView: {
                LUIText(subtitle.localized(), style: .body)
            }, bottomView: bottomView
        )
    }
}

struct BigSymbolView<V0: View, V1: View>: View {
    let symbol: String
    let textView: () -> V0
    let bottomView: () -> V1
    let title: String

    @Environment(\.colorScheme) private var colorScheme

    init(
        symbol: String, title: String, @ViewBuilder textView: @escaping () -> V0,
        bottomView: @escaping () -> V1
    ) {
        self.title = title
        self.symbol = symbol
        self.textView = textView
        self.bottomView = bottomView
    }

    var body: some View {
        let imageFontSize = 30.0

        VStack {
            if title == "" {
                Spacer()
            }

            if symbol != "" {
                ZStack {
                    getGradient(colors: luiModel.configuration.defaultColors)
                    LinearGradient(
                        colors: [.clear, .white.opacity(0.2)], startPoint: .bottom, endPoint: .top
                    )
                }
                .mask(
                    Image(systemName: symbol)
                        .font(.system(size: imageFontSize, weight: .heavy))
                )
                .frame(width: imageFontSize * 2, height: imageFontSize * 2)
            }

            if title != "" {
                LargeTitle(text: title, lineLimit: 2)
                    .padding()
                    .padding(.top, -21)
            }

            textView()
                .frame(maxWidth: luiModel.maxWidth)
                .padding(.horizontal, 40)
                .centered()
                .lowerOpacity(darkModeAsWell: true)
                .lineSpacing(7)

            Spacer()
            Spacer()

            bottomView()

            Spacer()
        }
    }
}
