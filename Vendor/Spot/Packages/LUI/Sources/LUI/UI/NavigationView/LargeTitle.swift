//
//  LargeTitle.swift
//
//
//  Created by Leon Böttger on 28.07.23.
//

import SwiftUI

public struct LargeTitle: View {
    private var text: String
    private var lineLimit: Int
    @ObservedObject var luiSettings = LUISettings.sharedInstance

    public init(text: String, lineLimit: Int = 1) {
        self.text = text
        self.lineLimit = lineLimit
    }

    public var body: some View {
        Text(text.localized())
            .multilineTextAlignment(.center)
            .modifier(LargeTitleModifier(lineLimit: lineLimit))
            .padding(.vertical, 0)
    }
}

struct LargeTitleModifier: ViewModifier {
    var lineLimit: Int
    @ObservedObject var luiSettings = LUISettings.sharedInstance

    func body(content: Content) -> some View {
        content
            .foregroundColor(.mainColor)
            .font(.system(size: 30, weight: .bold))
            .rounded()
            .lineLimit(lineLimit)
            .padding(.horizontal)
    }
}
