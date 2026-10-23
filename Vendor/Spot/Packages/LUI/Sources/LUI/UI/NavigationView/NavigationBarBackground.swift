//
//  NavigationBarBackground.swift
//
//
//  Created by Leon Böttger on 28.07.23.
//

import SwiftUI

func setNavigationBarColor() {
    configureNavigationBar(UINavigationBar.appearance(), usesNativeBackground: true)
}

func configureNavigationBar(_ navigationBar: UINavigationBar, usesNativeBackground: Bool) {
    let transparentAppearance = makeNavigationBarAppearance(withNativeBackground: false)
    let standardAppearance = usesNativeBackground
        ? makeNavigationBarAppearance(withNativeBackground: true)
        : transparentAppearance

    navigationBar.standardAppearance = standardAppearance
    navigationBar.compactAppearance = standardAppearance
    navigationBar.scrollEdgeAppearance = transparentAppearance
    navigationBar.compactScrollEdgeAppearance = transparentAppearance
}

private func makeNavigationBarAppearance(withNativeBackground: Bool) -> UINavigationBarAppearance {
    let appearance = UINavigationBarAppearance()

    if withNativeBackground {
        appearance.configureWithDefaultBackground()
    } else {
        appearance.configureWithTransparentBackground()
        appearance.backgroundColor = .clear
    }

    appearance.titleTextAttributes = [.foregroundColor: UIColor(.mainColor)]
    appearance.largeTitleTextAttributes = [.foregroundColor: UIColor(.mainColor)]
    return appearance
}
