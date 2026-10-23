//
//  CustomDivider.swift
//  LUIExample
//
//  Created by Leon Böttger on 12.08.23.
//

import SwiftUI

public struct LUIDivider: View {
    @Environment(\.colorScheme) var colorScheme

    public init() {}

    public var body: some View {
        Divider()
            .opacity(getOpacity())
    }

    func getOpacity() -> CGFloat {
        return 1

        return 1
    }
}
