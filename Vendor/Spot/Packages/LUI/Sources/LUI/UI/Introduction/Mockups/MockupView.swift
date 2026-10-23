//
//  MockupView.swift
//
//
//  Created by Leon Böttger on 15.03.24.
//

import SwiftUI

public struct ScreenTwinView<Content1: View, Content2: View>: View {
    public init(
        animated: Bool = false, backScreen: @escaping () -> Content1,
        frontScreen: @escaping () -> Content2
    ) {
        self.animated = animated
        self.backScreen = backScreen
        self.frontScreen = frontScreen
    }

    var animated: Bool = false
    let backScreen: () -> Content1
    let frontScreen: () -> Content2

    @State private var timer = Timer.publish(every: 2.5, on: .main, in: .common).autoconnect()

    @State private var inverted = false

    public var body: some View {
        let offset = 48.0

        ZStack {
            backScreen()
                .frame(width: 125, height: 222)
                .cornerRadius(8)
                .offset(x: inverted ? offset : -offset, y: inverted ? offset : 0)

            frontScreen()
                .frame(width: 125, height: 222)
                .cornerRadius(8)
                .compositingGroup()
                .shadow(color: .white, radius: 0.4)
                .offset(x: inverted ? -offset : offset, y: inverted ? 0 : offset)
                .zIndex(inverted ? -1 : 1)
        }
        .padding(.bottom, offset)
        .if(
            animated,
            transform: { view in
                view.onReceive(
                    timer,
                    perform: { _ in
                        withAnimation(Animation.interpolatingSpring(mass: 0.5, stiffness: 70, damping: 10)) {
                            inverted.toggle()
                        }
                    }
                )
            }
        )
    }
}
