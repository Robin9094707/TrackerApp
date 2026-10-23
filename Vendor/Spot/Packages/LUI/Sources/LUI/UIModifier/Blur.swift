//
//  Blur.swift
//
//
//  Created by Leon Böttger on 28.07.23.
//

import SwiftUI
import UIKit

public struct Blur: UIViewRepresentable {
    public init(style: UIBlurEffect.Style = .systemUltraThinMaterial) {
        self.style = style
    }

    public var style: UIBlurEffect.Style

    public func makeUIView(context _: Context) -> UIVisualEffectView {
        UIVisualEffectView(effect: UIBlurEffect(style: style))
    }

    public func updateUIView(_ uiView: UIVisualEffectView, context _: Context) {
        uiView.effect = UIBlurEffect(style: style)
    }
}

public struct TintedBlur: View {
    public init() {}

    @Environment(\.colorScheme) var colorScheme
    @Environment(\.sheetActive) var sheetActive

    public var body: some View {
        Blur(style: .systemUltraThinMaterial)
            .brightness(getBrightness())
    }

    func getBrightness() -> Double {
        if isiPadOrMac() {
            if colorScheme.isLight {
                return 0.023
            } else {
                if sheetActive {
                    return -0.065
                }

                return -0.1
            }
        }

        if colorScheme.isLight {
            return 0.02
        } else {
            if sheetActive {
                return -0.075
            }

            return -0.095
        }
    }
}
