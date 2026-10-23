//
//  IntroductionView.swift
//
//
//  Created by Leon Böttger on 23.08.22.
//

import SwiftUI

public struct IntroductionView<Content: View>: View {
    let firstPagedView: Content
    @StateObject private var controller = IntroductionViewController.sharedInstance

    public var body: some View {
        NavigationView {
            BottomBarView(
                navigationBarLayout: .LargeOnly,
                mainView: {
                    let symbol = getSymbol()

                    BigSymbolViewWithText(
                        symbol: symbol, subtitle: luiModel.configuration.introductionViewInformation,
                        title: String(
                            format: "introductionview_welcome_to".liblocalized(), luiModel.configuration.appName
                        )
                    ) {
                        ScreenTwinView(
                            backScreen: { AppMockupBackView() }, frontScreen: { AppMockupFrontView() }
                        )
                    }

                },
                bottomView: {
                    IntroductionButtonView(
                        label: "introductionview_continue_button".liblocalized(), action: pressedContinue
                    ) {
                        firstPagedView
                    }
                }
            )
        }
        .interactiveDismiss(canDismissSheet: false)
    }

    func getSymbol() -> String {
        "sparkle"
    }

    func pressedContinue() {
        IntroductionViewController.sharedInstance.canProceed = true
    }
}

public func finishedAppIntroduction() {
    if !LUISettings.sharedInstance.appLaunchedBefore {
        doubleVibration()

        LUISettings.sharedInstance.canShowIntroductionSheet = false

        runAfter(seconds: 0.7) {
            LUISettings.sharedInstance.appLaunchedBefore = true
        }
    }
}

public extension View {
    func gradientForeground(gradient: LinearGradient) -> some View {
        overlay(gradient)
            .mask(self)
    }
}
