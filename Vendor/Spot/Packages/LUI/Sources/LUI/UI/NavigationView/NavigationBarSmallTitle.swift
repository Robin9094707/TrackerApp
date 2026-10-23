//
//  NavigationBarSmallTitle.swift
//
//
//  Created by Leon Böttger on 01.08.23.
//

import SwiftUI

let dividerTransition = AnyTransition.asymmetric(
    insertion:
    AnyTransition
        .opacity
        .animation(.spring()),
    removal:
    AnyTransition
        .opacity
        .animation(.easeInOut(duration: 0.2))
)

struct NavigationBarSmallTitleModifier: ViewModifier {
    let header: String
    let supportsScrolling: Bool

    @State var navBarHeight: CGFloat = 44
    @State private var statusBarOpacity: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .if(
                supportsScrolling,
                transform: { view in
                    view.didScroll { point in
                        let scrollViewOffset = -point
                        statusBarOpacity = min(1, -scrollViewOffset * 10 / navBarHeight)
                    }
                }
            )
            .overlay(
                ZStack {
                    if supportsScrolling {
                        VStack {
                            GeometryReader { geometry in
                                TintedBlur()
                                    .frame(height: geometry.safeAreaInsets.top)
                                    .opacity(statusBarOpacity)
                                    .edgesIgnoringSafeArea(.top)
                                    .edgesIgnoringSafeArea(.vertical)

                                Spacer()
                            }
                        }
                    }

                    VStack(spacing: 0) {
                        HStack {
                            LUIText(header, isBold: true, ignoresDynamicType: true)
                                .lineLimit(1)
                                .opacity(statusBarOpacity)
                        }
                        .padding(.horizontal, 100)
                        .frame(height: navBarHeight)
                        .clipped()
                        .offset(y: -navBarHeight)
                        .transition(dividerTransition)

                        Spacer()
                    }

                    VStack {
                        if supportsScrolling {
                            LUIDivider()
                                .opacity(statusBarOpacity)
                        }

                        Spacer()
                    }
                }
            )
            .background(
                NavigationBarAccessor { navBar in
                    navBarHeight = min(50, navBar.bounds.height)
                }
            )
    }
}

extension View {
    func navigationBarSmallTitle(header: String, supportsScrolling: Bool)
        -> some View
    {
        modifier(
            NavigationBarSmallTitleModifier(
                header: header, supportsScrolling: supportsScrolling
            )
        )
    }
}

struct NavigationBarAccessor: UIViewControllerRepresentable {
    var callback: (UINavigationBar) -> Void
    private let proxyController = ViewController()

    func makeUIViewController(context _: UIViewControllerRepresentableContext<NavigationBarAccessor>)
        -> UIViewController
    {
        proxyController.callback = callback
        return proxyController
    }

    func updateUIViewController(
        _ uiViewController: UIViewController,
        context _: UIViewControllerRepresentableContext<NavigationBarAccessor>
    ) {
        guard let viewController = uiViewController as? ViewController else { return }

        viewController.callback = callback

        if let navigationBar = viewController.navigationController?.navigationBar {
            DispatchQueue.main.async {
                callback(navigationBar)
            }
        }
    }

    typealias UIViewControllerType = UIViewController

    private class ViewController: UIViewController {
        var callback: (UINavigationBar) -> Void = { _ in }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)

            if let navBar = navigationController {
                callback(navBar.navigationBar)
            }
        }
    }
}
