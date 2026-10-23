//
//  SymbolMockupView.swift
//
//
//  Created by Leon Böttger on 15.03.24.
//

import SwiftUI

public struct SymbolMockupView: View {
    public init(symbol: String = "") {
        self.symbol = symbol
    }

    var symbol: String = ""

    public var body: some View {
        MockupColorBackground()
            .overlay(
                ZStack {
                    Image(systemName: symbol)
                        .font(.system(size: 38))
                        .foregroundColor(.white)
                }
            )
            .compositingGroup()
    }
}

struct MockupColorBackground: View {
    var body: some View {
        let color = luiModel.configuration.defaultColors.first

        ZStack {
            Color.defaultBackgroundColor
            color
            LinearGradient(colors: [.clear, .white.opacity(0.3)], startPoint: .bottom, endPoint: .top)
        }
    }
}
