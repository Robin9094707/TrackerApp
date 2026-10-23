//
//  LUIText.swift
//
//
//  Created by Leon Böttger on 30.07.23.
//

import SwiftUI

public struct LUIText: View {
    public init(
        _ text: String, style: Font.TextStyle = .body, isBold: Bool = false,
        ignoresDynamicType: Bool = false, centered: Bool = false, color: Color = .mainColor
    ) {
        self.isBold = isBold
        self.ignoresDynamicType = ignoresDynamicType
        self.text = text
        self.centered = centered
        self.color = color
        self.style = style
    }

    let isBold: Bool
    let ignoresDynamicType: Bool
    let text: String
    let centered: Bool
    let color: Color
    let style: Font.TextStyle

    public var body: some View {
        Text(text.localized())
            .font(.system(style))
            .if(
                isBold,
                transform: { text in
                    text.bold()
                }
            )

            .if(
                centered,
                transform: { text in
                    text.centered()
                }
            )

            .if(
                ignoresDynamicType,
                transform: { text in
                    text
                        .dynamicTypeSize(.medium)
                }
            )

            .foregroundColor(color)
            .rounded()
    }
}

struct RoundTextModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .fontDesign(.rounded)
    }
}

public extension View {
    func rounded() -> some View {
        // return self
        modifier(RoundTextModifier())
    }
}
