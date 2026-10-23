//
//  LUISheet.swift
//
//
//  Created by Leon Böttger on 17.08.23.
//

import SwiftUI

struct LUISheet<Content1: View>: ViewModifier {
    init(isPresented: Binding<Bool>, @ViewBuilder content: () -> Content1) {
        sheetContent = content()
        _isPresented = isPresented
    }

    let sheetContent: Content1
    @Binding var isPresented: Bool
    @ObservedObject var luiSettings = LUISettings.sharedInstance

    func body(content: Content) -> some View {
        content
            .sheet(
                isPresented: $isPresented,
                content: {
                    LUISheetContent(isPresented: $isPresented, sheetContent: sheetContent)
                }
            )
    }
}

struct LUISheetContent<Content: View>: View {
    @ObservedObject var luiSettings = LUISettings.sharedInstance

    @Binding var isPresented: Bool
    let sheetContent: Content

    var body: some View {
        sheetContent
            .background(
                ZStack {
                    LUIButton(
                        action: {
                            isPresented = false
                        },
                        label: {
                            EmptyView()
                        }
                    )

                    .keyboardShortcut(.cancelAction)
                }
            )
            .modifier(SheetCornerRadiusModifier())
            .environment(\.sheetActive, true)
            .accentColor(navigationBarItemColor)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .modifier(AlertOverlayModifier())
    }
}

struct SheetCornerRadiusModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .presentationCornerRadius(20)
    }
}

public extension View {
    func luiSheet(
        isPresented: Binding<Bool>, @ViewBuilder content: () -> some View
    ) -> some View {
        modifier(LUISheet(isPresented: isPresented, content: content))
    }
}

struct SizeKey: EnvironmentKey {
    static let defaultValue = CGSize.zero
}

struct SheetActiveKey: EnvironmentKey {
    static let defaultValue = false
}

public extension EnvironmentValues {
    var sheetActive: Bool {
        get { self[SheetActiveKey.self] }
        set { self[SheetActiveKey.self] = newValue }
    }

    var screenSize: CGSize {
        get { self[SizeKey.self] }
        set { self[SizeKey.self] = newValue }
    }
}

class ModalHostingController<Content: View>: UIHostingController<Content>,
    UIAdaptivePresentationControllerDelegate
{
    var canDismissSheet = true
    var onDismissalAttempt: (() -> Void)?

    override func willMove(toParent parent: UIViewController?) {
        super.willMove(toParent: parent)
        parent?.presentationController?.delegate = self
    }

    func presentationControllerShouldDismiss(_: UIPresentationController)
        -> Bool
    {
        canDismissSheet
    }

    func presentationControllerDidAttemptToDismiss(_: UIPresentationController) {
        onDismissalAttempt?()
    }
}

struct ModalView<T: View>: UIViewControllerRepresentable {
    let canDismissSheet: Bool
    let view: T
    let onDismissalAttempt: (() -> Void)?

    func makeUIViewController(context _: Context) -> ModalHostingController<T> {
        let controller = ModalHostingController(rootView: view)

        controller.canDismissSheet = canDismissSheet
        controller.onDismissalAttempt = onDismissalAttempt

        return controller
    }

    func updateUIViewController(_ uiViewController: ModalHostingController<T>, context _: Context) {
        uiViewController.rootView = view
        uiViewController.canDismissSheet = canDismissSheet
        uiViewController.onDismissalAttempt = onDismissalAttempt
    }
}

public extension View {
    func interactiveDismiss(canDismissSheet: Bool, onDismissalAttempt: (() -> Void)? = nil)
        -> some View
    {
        ModalView(
            canDismissSheet: canDismissSheet, view: self,
            onDismissalAttempt: onDismissalAttempt
        ).edgesIgnoringSafeArea(.all)
    }
}
