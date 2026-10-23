//
//  FormLabel.swift
//
//
//  Created by Leon Böttger on 28.07.23.
//

import SwiftUI

public struct SettingsLabel: View {
    public init(imageName: String, text: String, backgroundColor: Color = .blue) {
        self.imageName = imageName
        self.text = text
        self.backgroundColor = backgroundColor
    }

    let imageName: String
    let text: String
    var backgroundColor: Color
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled

    public var body: some View {
        HStack {
            SettingsIcon(imageName: imageName, backgroundColor: backgroundColor)

            LUIText(text.localized())
                .multilineTextAlignment(.leading)
                .minimumScaleFactor(0.8)
                .lineLimit(2)
            Spacer()
        }
        .frame(height: luiModel.SettingsLabelHeight)
        .frame(maxWidth: .infinity)
    }
}

public struct NavigationLinkLabel: View {
    public init(
        imageName: String, text: String, backgroundColor: Color = .blue, isNavLink: Bool = true,
        isLoading: Bool = false
    ) {
        self.imageName = imageName
        self.text = text
        self.backgroundColor = backgroundColor
        self.isNavLink = isNavLink
        self.isLoading = isLoading
    }

    let imageName: String
    let text: String
    var backgroundColor: Color
    var isNavLink: Bool
    let isLoading: Bool

    @Environment(\.isEnabled) private var isEnabled: Bool

    public var body: some View {
        HStack {
            SettingsLabel(imageName: imageName, text: text, backgroundColor: backgroundColor)

            Spacer()

            if isLoading {
                LoadingIndicator()
                    .frame(width: 19)
            } else {
                if isNavLink {
                    ArrowRightView()
                } else {
                    Image(systemName: "link")
                        .foregroundColor(.gray)
                }
            }
        }
        .animation(.easeInOut, value: isLoading)
        .opacity(isEnabled ? 1 : 0.5)
        .frame(height: luiModel.SettingsLabelHeight)
        .contentShape(Rectangle())
    }
}

public struct CustomPickerLabel: View {
    public init(
        selection: String, backgroundColor: Color = Color.blue, description: String, imageName: String,
        isLink: Bool = true
    ) {
        self.selection = selection
        self.backgroundColor = backgroundColor
        self.description = description
        self.imageName = imageName
        self.isLink = isLink
    }

    let selection: String
    var backgroundColor: Color
    let description: String
    let imageName: String
    var isLink: Bool

    public var body: some View {
        HStack {
            SettingsLabel(imageName: imageName, text: description, backgroundColor: backgroundColor)
            Spacer()
            LUIText(selection.localized(), color: .gray)
                .animation(nil)

            if isLink {
                ArrowRightView()
                    .padding(.leading, 5)
            }
        }
        .contentShape(Rectangle())
        .frame(height: luiModel.SettingsLabelHeight)
    }
}

public struct ArrowRightView: View {
    public init() {}

    public var body: some View {
        Image(systemName: "chevron.right")
            .foregroundColor(.gray)
    }
}

public struct SettingsIcon: View {
    public init(imageName: String, backgroundColor: Color) {
        self.imageName = imageName
        self.backgroundColor = backgroundColor
    }

    let imageName: String
    let backgroundColor: Color

    let size: CGFloat = 30

    @Environment(\.colorScheme) private var colorScheme

    public var body: some View {
        ZStack {
            ZStack {
                if backgroundColor == .green, colorScheme.isDark {
                    gradient()
                } else {
                    backgroundColor
                    LinearGradient(
                        colors: [.clear, .white.opacity(0.1)], startPoint: .bottom, endPoint: .top
                    )
                }
            }
            .mask(Circle())

            ZStack {
                let sizeReduction =
                    imageName.contains("person.2") || imageName.contains("person.3")
                        ? 3.0 : (imageName.contains("battery.") ? 2.5 : 2.0)

                Image(systemName: imageName)
                    .font(.system(size: size / sizeReduction, weight: .bold))
            }

            .foregroundColor(.white)
            .clipped()
        }
        .frame(width: size, height: size)
        .padding(.trailing, 5)
        .compositingGroup()
    }

    func gradient() -> LinearGradient {
        getGradient(colors: [
            Color(#colorLiteral(red: 0.5843137503, green: 0.8235294223, blue: 0.4196078479, alpha: 1)),
            Color(#colorLiteral(red: 0.1936409473, green: 0.7672969699, blue: 0.3610956669, alpha: 1)),
        ])
    }
}
