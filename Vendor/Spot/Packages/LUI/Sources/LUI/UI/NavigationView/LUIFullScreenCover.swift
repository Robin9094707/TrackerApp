//
//  LUIFullScreenCover.swift
//  LUI
//
//  Created by Leon Böttger on 20.10.24.
//

import SwiftUI

struct LUIFullScreenCover<Content1: View>: ViewModifier {
    init(isPresented: Binding<Bool>, @ViewBuilder content: () -> Content1) {
        sheetContent = content()
        _isPresented = isPresented
    }

    let sheetContent: Content1
    @Binding var isPresented: Bool

    func body(content: Content) -> some View {
        content
            .fullScreenCover(
                isPresented: $isPresented,
                content: {
                    LUISheetContent(isPresented: $isPresented, sheetContent: sheetContent)
                }
            )
    }
}

public extension View {
    func luiFullScreenCover(
        isPresented: Binding<Bool>, @ViewBuilder content: () -> some View
    ) -> some View {
        modifier(LUIFullScreenCover(isPresented: isPresented, content: content))
    }
}
