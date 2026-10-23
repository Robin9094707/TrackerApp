//
//  LUIModel.swift
//
//
//  Created by Leon Böttger on 28.07.23.
//

import SwiftUI
import SwiftUIIntrospect

@MainActor
public class IntrospectModel {
    public static let introspectScrollViewVersions = PlatformViewVersionPredicate<
        ScrollViewType, UIScrollView
    >.iOS(.v13, .v14, .v15, .v16, .v17, .v18)
}

public class LUIModel {
    private init() {}

    static var sharedInstance = LUIModel()

    public let cornerRadius: CGFloat = 25

    public let SettingsLabelHeight: CGFloat = 55
    private static let height: CGFloat = 80

    public let BottomBarHeight: CGFloat = LUIModel.height
    public let BottomBarHeightWithSkip: CGFloat = LUIModel.height + 45

    public let textFieldOffset = (LUIModel.height * 1.5) / 2

    /// Spacing of sections for CustomForm.
    public let SettingsSectionSpacing: CGFloat = 15

    /// Maximum width of UI. Relevant for iPad screens.
    public let maxWidth: CGFloat = 700

    public var configuration = LUIConfiguration(
        appName: "Spot", defaultColors: [.blue, .blue], copyrightInformation: "",
        introductionViewInformation: ""
    )
}
