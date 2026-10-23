//
//  SpotMockup.swift
//  LUI
//
//  Created by Leon Böttger on 12.12.24.
//

import SwiftUI

struct SpotMockupView: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        (colorScheme.isLight ? Color.white : Color.sheetBackgroundColor)
            .overlay(
                VStack {
                    Text("Spot")
                        .foregroundColor(.mainColor)
                        .rounded()
                        .font(.system(size: 15, weight: .semibold))
                        .padding(.top)
                        .padding(.bottom, 10)

                    ForEach(0 ..< 4) { _ in
                        RoundedRectangle(cornerRadius: 10)
                            .frame(width: 80, height: 15)
                            .foregroundColor(.gray.opacity(0.3))
                            .padding(.bottom, 2)
                    }
                    Spacer()
                    Spacer()
                }
            )
    }
}

struct SpotSecondaryMockupView: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        SymbolMockupView(symbol: "map.fill")
    }
}
