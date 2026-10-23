//
//  SingleColumnRootView.swift
//
//
//  Created by Leon Böttger on 10.03.24.
//

import SwiftUI

struct SingleColumnRootView<Phone: View, Introduction: View>: View {
    let phoneView: () -> Phone
    let firstIntroductionView: () -> Introduction
    let appLaunchedBefore: Bool
    @ObservedObject private var settings = LUISettings.sharedInstance

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if !appLaunchedBefore, settings.canShowIntroductionSheet {
                    IntroductionSheet(firstIntroductionView: firstIntroductionView)
                } else {
                    NavigationView { phoneView() }.navigationViewStyle(.stack)
                }
            }
            .environment(\.screenSize, geometry.size)
        }
    }
}
