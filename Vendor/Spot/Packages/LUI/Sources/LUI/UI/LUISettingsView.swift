//
//  LUISettingsView.swift
//
//
//  Created by Leon Böttger on 06.08.23.
//

import SwiftUI

public struct LUISettingsView<Content: View>: View {
    @ObservedObject var luiSettings = LUISettings.sharedInstance

    let view: Content

    public init(@ViewBuilder content: () -> Content) {
        view = content()
    }

    public var body: some View {
        let settingsTitle = "settingsview_header".liblocalized()

        NavigationView {
            NavigationSubView(header: settingsTitle) {
                VStack(spacing: luiModel.SettingsSectionSpacing) {
                    view

                    CustomSection(header: "settingsview_more_header".liblocalized()) {
                        PrivacyPolicyLink()
                        AppInfoLink(showPrivacyPolicy: false)
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Close", systemImage: "xmark") {
                            LUISettings.sharedInstance.showSettings = false
                        }
                        .labelStyle(.iconOnly)
                    }
                }
            }
        }
    }
}

struct PrivacyPolicyLink: View {
    var body: some View {
        let label = "settingsview_more_privacy_policy"

        if let url = URL(string: privacyPolicyURL) {
            LUIURLButton(destination: url) {
                NavigationLinkLabel(
                    imageName: "hand.raised.fill", text: label.liblocalized(), backgroundColor: .red,
                    isNavLink: false
                )
            }
        }
    }
}

public struct LUIURLButton<Content: View>: View {
    public init(destination: URL, content: @escaping () -> Content) {
        self.destination = destination
        self.content = content
    }

    let content: () -> Content
    let destination: URL

    public var body: some View {
        Link(destination: destination, label: content)
            .buttonStyle(LUIButtonStyle())
    }
}

public let privacyPolicyURL = "settings_privacy_policy_url".liblocalized()
