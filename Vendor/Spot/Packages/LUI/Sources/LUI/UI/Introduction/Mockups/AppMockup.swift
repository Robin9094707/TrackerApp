//
//  AppMockup.swift
//
//
//  Created by Leon Böttger on 15.03.24.
//

import SwiftUI

public struct AppMockupFrontView: View {
    public init() {}
    public var body: some View {
        SpotMockupView()
    }
}

struct AppMockupBackView: View {
    var body: some View {
        SpotSecondaryMockupView()
    }
}
