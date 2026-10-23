//
//  NavigationSubView.swift
//
//
//  Created by Leon Böttger on 24.10.22.
//

import SwiftUI
import SwiftUIIntrospect

public enum NavigationBarCases {
    case Default
    case LargeOnly
    case SmallOnly
    case SmallOnlyAlways
}

var defaultBottomPadding: CGFloat {
    20
}

public struct NavigationSubView<Content: View>: View {
    let content: Content
    let spacing: CGFloat
    let bottomPadding: CGFloat
    let minHeight: CGFloat

    private let headerText: String

    private var supportsScrolling: Bool
    private var backgroundShown: Bool
    private var refreshAction: (() async -> Void)?

    private var navigationBarLayout: NavigationBarCases

    public init(
        spacing: CGFloat = luiModel.SettingsSectionSpacing,
        header: String? = "",
        bottomPadding: CGFloat = 0,
        minHeight: CGFloat = 0,
        navigationBarLayout: NavigationBarCases = .Default,
        hideSmallHeader _: Bool = false,
        supportsScrolling: Bool = true,
        refreshAction: (() async -> Void)? = nil,
        backgroundShown: Bool = true,
        @ViewBuilder content: () -> Content
    ) {
        self.content = content()
        self.spacing = spacing
        self.bottomPadding = bottomPadding
        self.minHeight = minHeight
        self.navigationBarLayout = navigationBarLayout
        self.supportsScrolling = supportsScrolling
        self.backgroundShown = backgroundShown
        self.refreshAction = refreshAction

        headerText = header ?? ""
    }

    public var body: some View {
        GeometryReader { geo in
            ZStack {
                if supportsScrolling {
                    ScrollView(showsIndicators: false) {
                        NavigationContentView(
                            supportsScrolling: true,
                            content: { content }
                        )

                        .padding(.bottom, bottomPadding + defaultBottomPadding)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: max(minHeight, geo.size.height))
                        .padding(.top, headerText.isEmpty ? -14 : -3)
                    }
                    .if(
                        refreshAction != nil,
                        transform: {
                            $0.refreshable {
                                await refreshAction?()
                            }
                        }
                    )
                    .introspect(.scrollView, on: IntrospectModel.introspectScrollViewVersions) { scrollView in
                        scrollView.keyboardDismissMode = .interactive
                    }
                } else {
                    NavigationContentView(
                        supportsScrolling: false,
                        content: { content }
                    )
                    .frame(maxHeight: .infinity)
                    .frame(maxWidth: .infinity)
                    .padding(.top, headerText.isEmpty ? -14 : 0)
                }
            }

            .if(
                backgroundShown,
                transform: { view in
                    view.modifier(CustomFormBackground())
                }
            )
            .if(navigationBarLayout == .SmallOnly, transform: { view in
                view
                    .navigationBarSmallTitle(header: headerText, supportsScrolling: supportsScrolling)
                    .navigationBarTitle("‎‎‏‏‎ ‎", displayMode: .inline)
            })
            .if(navigationBarLayout != .SmallOnly, transform: { view in
                view
                    .navigationTitle(headerText.isEmpty ? "‎‎‏‏‎ ‎" : headerText.localized())
                    .navigationBarTitleDisplayMode(
                        headerText.isEmpty || navigationBarLayout == .SmallOnlyAlways ? .inline : .large
                    )
            })
            .background(NavigationBarAccessor { navigationBar in
                configureNavigationBar(navigationBar, usesNativeBackground: navigationBarLayout != .SmallOnly)
            })
        }
    }
}

private struct NavigationContentView<Content: View>: View {
    let supportsScrolling: Bool
    let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: luiModel.SettingsSectionSpacing) {
                content()
            }

            if supportsScrolling {
                Spacer()
            }
        }
    }
}

struct CustomFormBackground: ViewModifier {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.sheetActive) var sheetActive

    func body(content: Content) -> some View {
        let color = backgroundColor(sheetActive)

        content
            .background(color.ignoresSafeArea())
    }
}
