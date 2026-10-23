//
//  HelpersUIKit.swift
//
//
//  Created by Leon Böttger on 30.07.23.
//

import SwiftUI
import UIKit

extension UINavigationController: UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_: UIGestureRecognizer) -> Bool {
        LUISettings.sharedInstance.appLaunchedBefore && viewControllers.count > 1
    }
}

extension UIApplication {
    var myKeyWindow: UIWindow? {
        connectedScenes
            .compactMap {
                $0 as? UIWindowScene
            }
            .flatMap(\.windows)
            .first {
                $0.isKeyWindow
            }
    }
}

public struct KeyboardListener: ViewModifier {
    public init(keyboardShowing: Binding<Bool>) {
        _keyboardShowing = keyboardShowing
    }

    @Binding var keyboardShowing: Bool

    public func body(content: Content) -> some View {
        content

            .onReceive(
                NotificationCenter.default.publisher(for: UITextField.textDidBeginEditingNotification)
            ) { _ in
                withAnimation {
                    keyboardShowing = true
                }
            }

            .onReceive(
                NotificationCenter.default.publisher(for: UITextField.textDidEndEditingNotification)
            ) { _ in
                withAnimation {
                    keyboardShowing = false
                }
            }
    }
}
