//
//  PermissionView.swift
//
//
//  Created by Leon Böttger on 21.09.23.
//

import SwiftUI

public struct PermissionView<V0: View, V1: View, V2: View, V3: View>: View {
    let title: String
    let symbol: String
    let subtitle: String
    let action: () -> Void
    let continueLabel: String
    let canSkip: Bool
    let skipLabel: String
    let destination: () -> V0
    let skipDestination: () -> V1
    let frontMockup: () -> V2
    let backMockup: () -> V3
    let animateMockup: Bool

    public init(
        title: String, symbol: String, subtitle: String,
        permissionAction: @escaping () -> Void = {
            IntroductionViewController.sharedInstance.canProceed = true
        }, continueLabel: String = "introductionview_continue_button", canSkip: Bool = true,
        skipLabel: String = "introduction_skip_button", animateMockup: Bool = false,
        @ViewBuilder nextView: @escaping () -> V0, @ViewBuilder nextViewSkip: @escaping () -> V1,
        @ViewBuilder frontMockup: @escaping () -> V2, @ViewBuilder backMockup: @escaping () -> V3
    ) {
        self.title = title
        self.symbol = symbol
        self.subtitle = subtitle
        action = permissionAction
        self.canSkip = canSkip
        self.continueLabel = continueLabel.liblocalized()
        self.skipLabel = skipLabel.liblocalized()
        destination = nextView
        skipDestination = nextViewSkip
        self.frontMockup = frontMockup
        self.backMockup = backMockup
        self.animateMockup = animateMockup
    }

    public var body: some View {
        let height =
            canSkip && continueLabel != "" ? luiModel.BottomBarHeightWithSkip : luiModel.BottomBarHeight

        BottomBarView(
            header: "", navigationBarLayout: .LargeOnly, bottomViewHeight: height,
            mainView: {
                BigSymbolViewWithText(symbol: symbol, subtitle: subtitle, title: title) {
                    ScreenTwinView(animated: animateMockup, backScreen: backMockup, frontScreen: frontMockup)
                }
            },
            bottomView: {
                VStack(spacing: 0) {
                    HStack {
                        if canSkip {
                            SkipPermissionButton(label: skipLabel, destination: skipDestination)
                        }
                        if animateMockup {
                            LoadingIndicator()
                                .frame(width: 20)
                        }
                    }

                    if continueLabel != "" {
                        Spacer()

                        IntroductionButtonView(label: continueLabel, action: action, nextView: destination)

                        Spacer()
                    }
                }
            }
        )
    }
}

public struct SkipPermissionButton<Content: View>: View {
    public init(label: String, destination: @escaping () -> Content) {
        self.label = label.liblocalized()
        self.destination = destination
    }

    @State private var linkActive = false
    var label: String
    let destination: () -> Content

    public var body: some View {
        LUIButton(
            action: {
                linkActive = true
            },
            label: {
                Text(label.localized())
                    .padding()
                    .rounded()
                    .foregroundColor(.blue)
            }
        )

        .modifier(
            LinkTo(
                content: {
                    destination()
                }, isActive: $linkActive
            )
        )
    }
}
