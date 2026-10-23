//
//  DoneView.swift
//
//
//  Created by Leon Böttger on 21.09.23.
//  Copyright © 2023 Leon Böttger.
//

import SwiftUI

public struct IntroductionDoneView: View {
    public init() {}

    public var body: some View {
        BottomBarView(
            navigationBarLayout: .LargeOnly,
            mainView: {
                BigSymbolViewWithText(
                    symbol: getSymbol(),
                    subtitle: String(
                        format: "introduction_done_subheader".liblocalized(), luiModel.configuration.appName
                    ),
                    title: "introduction_done_header".liblocalized(),
                    bottomView: {
                        ScreenTwinView {
                            SymbolMockupView(symbol: "sparkles")
                        } frontScreen: {
                            AppMockupFrontView()
                        }
                    }
                )

            },
            bottomView: {
                LargeButton2(
                    label: "introductionview_continue_button".liblocalized(), action: finishedAppIntroduction
                )
            }
        )
    }

    func getSymbol() -> String {
        "checkmark"
    }
}
