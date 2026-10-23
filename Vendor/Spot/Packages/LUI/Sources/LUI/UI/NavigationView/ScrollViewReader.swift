//
//  ScrollViewReader.swift
//
//
//  Created by Leon Böttger on 29.07.23.
//

import Combine
import SwiftUI

func getScrollViewOffset(contentOffset: CGFloat, scrollview: UIScrollView) -> CGFloat {
    contentOffset + scrollview.adjustedContentInset.top
}

struct ScrollViewDidScrollViewModifier: ViewModifier {
    class ViewModel: ObservableObject {
        @Published var contentOffset: CGFloat = 0

        var contentOffsetSubscription: AnyCancellable?

        func subscribe(scrollView: UIScrollView) {
            contentOffsetSubscription = scrollView.publisher(for: \.contentOffset).sink {
                [weak self] contentOffset in
                let offset = getScrollViewOffset(contentOffset: contentOffset.y, scrollview: scrollView)

                DispatchQueue.main.async {
                    self?.contentOffset = offset
                }
            }
        }
    }

    @Environment(\.safeAreaInsets) private var safeAreaInsets
    @StateObject var viewModel = ViewModel()
    var didScroll: (CGFloat) -> Void

    func body(content: Content) -> some View {
        content
            .introspect(.scrollView, on: IntrospectModel.introspectScrollViewVersions) { scrollView in
                if viewModel.contentOffsetSubscription == nil {
                    viewModel.subscribe(scrollView: scrollView)
                }
            }
            .onReceive(viewModel.$contentOffset) { contentOffset in
                didScroll(contentOffset)
            }
    }
}

public extension View {
    func didScroll(_ didScroll: @escaping (CGFloat) -> Void) -> some View {
        modifier(ScrollViewDidScrollViewModifier(didScroll: didScroll))
    }
}
