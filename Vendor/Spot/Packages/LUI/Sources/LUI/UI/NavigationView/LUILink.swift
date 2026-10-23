//
//  LUILink.swift
//
//
//  Created by Leon Böttger on 15.08.23.
//

import SwiftUI

public struct LUILink<Content1: View, Content2: View>: View {
    public init(
        destination: Content1,
        isActive: Binding<Bool>? = nil,
        @ViewBuilder label: () -> Content2 = { EmptyView() }
    ) {
        self.destination = destination
        self.label = label()

        if let isActive {
            _isActive = isActive
            supportsIsActive = true
        } else {
            _isActive = .constant(false)
            supportsIsActive = false
        }
    }

    let destination: Content1
    let label: Content2

    @Binding var isActive: Bool
    let supportsIsActive: Bool
    @Environment(\.sheetActive) private var sheetActive

    public var body: some View {
        if supportsIsActive {
            NavigationLink(
                destination: destination.environment(\.sheetActive, sheetActive),
                isActive: $isActive
            ) {
                label
            }
            .buttonStyle(LUIButtonStyle())
        } else {
            NavigationLink(
                destination: destination.environment(\.sheetActive, sheetActive),
                label: {
                    label
                }
            )
            .buttonStyle(LUIButtonStyle())
        }
    }
}
