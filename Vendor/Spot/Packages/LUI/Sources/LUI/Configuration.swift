//
//  Configuration.swift
//
//
//  Created by Leon Böttger on 01.08.23.
//

import SwiftUI

public struct LUIConfiguration {
    public let appName: String
    public let defaultColors: [Color]
    public let copyrightInformation: String
    public let introductionViewInformation: String

    public init(
        appName: String, defaultColors: [Color], copyrightInformation: String,
        introductionViewInformation: String
    ) {
        self.appName = appName
        self.defaultColors = defaultColors
        self.copyrightInformation = copyrightInformation
        self.introductionViewInformation = introductionViewInformation
    }
}

public let luiModel = LUIModel.sharedInstance
public func LUIInit(configuration: LUIConfiguration) {
    luiModel.configuration = configuration
}
