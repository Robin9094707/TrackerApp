//
//  BottomBarView.swift
//
//
//  Created by Leon Böttger on 29.07.23.
//

import SwiftUI
import SwiftUIIntrospect

func backgroundColor(_ isSheet: Bool) -> Color {
    isSheet ? .sheetBackgroundColor : .defaultBackgroundColor
}

func foregroundColor(_ isSheet: Bool) -> Color {
    isSheet ? .sheetForegroundColor : .defaultForegroundColor
}

public struct BottomBarViewGeneric<Content1: View, Content2: View>: View {
    public init(
        bottomViewHeight: CGFloat = luiModel.BottomBarHeight,
        @ViewBuilder mainView: @escaping (CGFloat, CGFloat) -> Content1,
        @ViewBuilder bottomView: () -> Content2
    ) {
        self.bottomViewHeight = bottomViewHeight
        self.mainView = mainView
        self.bottomView = bottomView()
    }

    @Environment(\.colorScheme) private var colorScheme
    @State private var bottomOpacity = 0.0
    let bottomViewHeight: CGFloat
    let mainView: (CGFloat, CGFloat) -> Content1
    let bottomView: Content2
    @Environment(\.safeAreaInsets) private var safeAreaInsets
    @Environment(\.sheetActive) private var sheetActive

    @State var keyboardShowing = false
    @State private var scrollView: UIScrollView? = nil

    public var body: some View {
        ZStack {
            GeometryReader { geometry in
                ZStack {
                    let bottomPadding = bottomViewHeight
                    let minHeight = geometry.size.height - bottomViewHeight

                    mainView(bottomPadding, minHeight)
                }
                .introspect(.scrollView, on: IntrospectModel.introspectScrollViewVersions) { sv in
                    DispatchQueue.main.async {
                        scrollView = sv
                    }
                }
                .didScroll { scrollOffset in
                    calculateBottomOpacity(scrollOffset: scrollOffset)
                }
            }

            // button
            GeometryReader { geo in
                VStack(spacing: 0) {
                    Spacer()

                    let addPadding = geo.safeAreaInsets.bottom == 0 ? 7.0 : 0

                    bottomView
                        .padding(.bottom, addPadding)
                        .frame(maxWidth: .infinity)
                        .frame(height: bottomViewHeight + addPadding)
                        .background(
                            ZStack {
                                (LUI.foregroundColor(sheetActive))
                                    .mask(
                                        LinearGradient(
                                            gradient: Gradient(stops: [
                                                .init(color: .black.opacity(0), location: 0),
                                                .init(color: .black.opacity(0.8), location: 0.5),
                                            ]), startPoint: .top, endPoint: .bottom
                                        )
                                    )
                                    .padding(.top, -15)
                                    .padding(.bottom, geo.safeAreaInsets.bottom == 0 ? 0 : -35)
                                    .opacity(keyboardShowing ? 1 : bottomOpacity)
                                    .modifier(KeyboardListener(keyboardShowing: $keyboardShowing))
                            }
                            .opacity(1)
                        )
                }
            }
        }
    }

    private func calculateBottomOpacity(scrollOffset: CGFloat) {
        guard let scrollView else { return }

        let visibleScrollView = scrollView.frame.size.height - bottomViewHeight - safeAreaInsets.bottom

        let visibleContentHeight = scrollView.contentSize.height - scrollOffset - defaultBottomPadding

        if visibleContentHeight < visibleScrollView {
            bottomOpacity = 0.0
        } else {
            let diff = visibleContentHeight - visibleScrollView
            let scale = diff / 20
            bottomOpacity = min(1, scale)
        }
    }
}

public struct BottomBarView<Content1: View, Content2: View>: View {
    public init(
        header: String? = "",
        navigationBarLayout: NavigationBarCases = .Default,
        bottomViewHeight: CGFloat = luiModel.BottomBarHeight,
        backgroundShown: Bool = true,
        @ViewBuilder mainView: () -> Content1,
        @ViewBuilder bottomView: () -> Content2
    ) {
        self.bottomViewHeight = bottomViewHeight
        self.mainView = mainView()
        self.bottomView = bottomView()
        self.navigationBarLayout = navigationBarLayout
        self.backgroundShown = backgroundShown

        headerText = header ?? ""
    }

    private var navigationBarLayout: NavigationBarCases
    private let backgroundShown: Bool
    private let headerText: String

    @Environment(\.colorScheme) private var colorScheme
    @State private var bottomOpacity = 0.0
    let bottomViewHeight: CGFloat
    let mainView: Content1
    let bottomView: Content2
    @Environment(\.safeAreaInsets) private var safeAreaInsets
    @Environment(\.sheetActive) private var sheetActive

    @State var keyboardShowing = false
    @State private var scrollView: UIScrollView? = nil

    public var body: some View {
        BottomBarViewGeneric(bottomViewHeight: bottomViewHeight) { bottomPadding, minHeight in
            NavigationSubView(
                header: headerText,
                bottomPadding: bottomPadding,
                minHeight: minHeight,
                navigationBarLayout: navigationBarLayout,
                backgroundShown: backgroundShown
            ) {
                mainView
            }

        } bottomView: {
            bottomView
        }
    }
}
