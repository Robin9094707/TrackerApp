//
//  Paging.swift
//
//
//  Created by Leon Böttger on 21.09.23.
//

import SwiftUI

public struct LinkTo<V0: View>: ViewModifier {
    @Binding var isActive: Bool
    let destination: () -> V0

    public init(@ViewBuilder content: @escaping () -> V0, isActive: Binding<Bool>) {
        destination = content
        _isActive = isActive
    }

    public func body(content: Content) -> some View {
        content
            .background(
                LUILink(destination: destination(), isActive: $isActive)
                    .disabled(true)
                    .hidden()
            )
    }
}

public class IntroductionViewController: ObservableObject {
    public static var sharedInstance = IntroductionViewController()

    private init() {}

    @Published public var canProceed = false {
        didSet {}
    }
}

struct IntroductionButtonView<V0: View>: View {
    @State private var linkActive = false
    let action: () -> Void
    let label: String
    private let destination: () -> V0

    @Environment(\.colorScheme) var colorScheme
    @ObservedObject var controller = IntroductionViewController.sharedInstance

    init(label: String, action: @escaping () -> Void, @ViewBuilder nextView: @escaping () -> V0) {
        self.label = label
        destination = nextView
        self.action = action
    }

    var body: some View {
        LargeButton2(
            label: label, lighter: colorScheme.isDark && isiPadOrMac(), action: pressedContinue
        )
        .modifier(LinkTo(content: destination, isActive: $linkActive))
        .onChange(of: controller.canProceed) { newValue in
            if newValue, !linkActive {
                controller.canProceed = false
                linkActive = true
            }
        }
    }

    func pressedContinue() {
        if controller.canProceed {
            controller.canProceed = false
            linkActive = true
        } else {
            action()
        }
    }
}
