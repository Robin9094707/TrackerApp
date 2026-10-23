//
//  CustomForm.swift
//
//
//  Created by Leon Böttger on 28.07.23.
//

import SwiftUI

public struct CustomSection<Content: View>: View {
    @Environment(\.colorScheme) var colorScheme
    let content: Content
    let header: String
    let footer: String
    let backgroundColor: Color?

    public init(
        header: String = "",
        footer: String = "",
        backgroundColor: Color? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.content = content()
        self.header = header
        self.footer = footer
        self.backgroundColor = backgroundColor
    }

    public var body: some View {
        VStack {
            if header != "" {
                FormHeader(name: header.localized())
            }

            VStack(spacing: 0) {
                DividerView {
                    content
                }
            }
            .modifier(CustomFormModifier(backgroundColor: backgroundColor))

            if footer != "" {
                FooterView(text: footer)
            }
        }
        .padding(.horizontal)
        .padding(.top, 15)
    }
}

public struct FooterView: View {
    public init(text: String) {
        self.text = text
    }

    let text: String
    @Environment(\.colorScheme) private var colorScheme

    public var body: some View {
        Text(text.localized())
            .fixedSize(horizontal: false, vertical: true)
            .foregroundColor(.grayColor.opacity(colorScheme.isLight ? 1 : 0.8))
            .font(.system(.footnote))
            .rounded()
            .lineSpacing(2)
            .padding(.top, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
    }
}

struct CustomFormModifier: ViewModifier {
    let backgroundColor: Color?

    @Environment(\.colorScheme) var colorScheme
    @Environment(\.sheetActive) private var sheetActive

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity)
            .padding(.horizontal)
            .background(
                ZStack {
                    colorScheme.isLight ? Color.white : Color.white.opacity(0.04)

                    if let backgroundColor {
                        backgroundColor
                    } else {
                        foregroundColor(sheetActive)
                    }
                }
            )
            .cornerRadius(luiModel.cornerRadius)
            .compositingGroup()
    }
}

public struct FormHeader: View {
    public init(name: String) {
        self.name = name
    }

    let name: String

    public var body: some View {
        HStack {
            HStack(spacing: 4) {
                Text(name.localized())
            }
            .rounded()
            .font(.footnote.weight(.medium))
            .foregroundColor(.grayColor)
            .contentShape(Rectangle())

            Spacer()
        }
        .padding(.horizontal, 7)
    }
}

struct DividerView<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        _VariadicView.Tree(DividerLayout()) {
            content
        }
    }

    struct DividerLayout: _VariadicView_MultiViewRoot {
        @ViewBuilder
        func body(children: _VariadicView.Children) -> some View {
            let last = children.last?.id

            ForEach(children) { child in
                child

                if child.id != last {
                    LUIDivider()
                }
            }
        }
    }
}
