//
//  AppInfoView.swift
//
//
//  Created by Leon Böttger on 30.07.23.
//

import SwiftUI

private let appNameForOsString = String(
    format: "informationview_for_os".liblocalized(), luiModel.configuration.appName, getOSName()
)
private let appVersionString = "informationview_version".liblocalized() + " \(getAppVersion())"

public struct AppInfoView: View {
    public init(showPrivacyPolicy: Bool = false) {
        copyrightInformation = luiModel.configuration.copyrightInformation
        self.showPrivacyPolicy = showPrivacyPolicy
    }

    private let copyrightInformation: String
    private let showPrivacyPolicy: Bool

    public var body: some View {
        let supportMail = luiModel.configuration.appName.lowercased() + "@leonboettger.com"

        NavigationSubView(
            header: "informationview_header".liblocalized(), navigationBarLayout: .SmallOnly
        ) {
            VStack(spacing: 0) {
                AppIconView()
                    .padding(.top, -15)

                LUIText(appNameForOsString, centered: true)
                    .padding(.bottom, 3)

                LUIText(appVersionString)
                    .opacity(0.5)
            }

            if showPrivacyPolicy {
                CustomSection(
                    footer: String(format: "informationview_contact_footer".liblocalized(), supportMail)
                ) {
                    PrivacyPolicyLink()
                    MailLink(supportMail: supportMail)
                }
            } else {
                CustomSection(
                    footer: String(format: "informationview_contact_footer".liblocalized(), supportMail)
                ) {
                    MailLink(supportMail: supportMail)
                }
            }

            LUILink(
                destination:
                NavigationSubView(header: "informationview_used_software".liblocalized()) {
                    CustomSection {
                        CopyrightText(copyrightInformation: copyrightInformation)
                    }
                },
                label: {
                    UnderlineText(label: "informationview_used_software".liblocalized())
                }
            )
            .padding(.top, isiPadOrMac() ? 7 : 20)
            .padding(.bottom, 20)
        }
    }
}

public struct UnderlineText: View {
    public init(label: String) {
        self.label = label
    }

    let label: String

    public var body: some View {
        Text(label.localized())
            .font(.system(size: 13))
            .foregroundColor(.grayColor)
            .underline(true)
    }
}

public struct CopyrightText: View {
    let copyrightInformation: String

    public var body: some View {
        LazyVStack {
            LUIText(
                "informationview_copyright_text".liblocalized() + "\n\n" + copyright + "\n\n\n"
                    + copyrightInformation.localized()
            )
            .padding(.vertical)
        }
    }
}

public struct MailLink: View {
    let supportMail: String

    public var body: some View {
        let color = Color(
            #colorLiteral(red: 0.2392156869, green: 0.6745098233, blue: 0.9686274529, alpha: 1)
        )

        LUIButton(action: {
            writeMail(to: supportMail)
        }) {
            NavigationLinkLabel(
                imageName: getContactIcon(), text: "informationview_more_contact".liblocalized(),
                backgroundColor: color, isNavLink: false
            )
        }
    }

    func getContactIcon() -> String {
        return "bubble.fill"

        return "square.and.pencil"
    }

    func writeMail(to address: String) {
        let systemVersion = UIDevice.current.systemVersion

        if let url = URL(
            string:
            "mailto:\(address.localized())?subject=\(appNameForOsString) \(appVersionString)&body=\n\n\(getDeviceModel()) - \(systemVersion)"
        ) {
            openURL(url: url)
        }
    }
}

func getDeviceModel() -> String {
    var systemInfo = utsname()
    uname(&systemInfo)
    let machineMirror = Mirror(reflecting: systemInfo.machine)
    return machineMirror.children.compactMap { element in
        guard let value = element.value as? Int8, value != 0 else { return nil }
        return String(UnicodeScalar(UInt8(value)))
    }.joined()
}

public struct AppInfoLink: View {
    public init(showPrivacyPolicy: Bool) {
        self.showPrivacyPolicy = showPrivacyPolicy
    }

    let showPrivacyPolicy: Bool

    public var body: some View {
        let label = "settingsview_information_and_contact"

        LUILink(
            destination: AppInfoView(showPrivacyPolicy: showPrivacyPolicy),
            label: {
                NavigationLinkLabel(
                    imageName: "info", text: label.liblocalized(), backgroundColor: Color.green
                )
            }
        )
    }
}

public struct AppIconView: View {
    public init() {}
    private let iconSize: CGFloat = 84
    public var body: some View {
        ZStack {
            if let uiImage = UIImage(named: "AppIconHighRes") {
                Image(uiImage: uiImage)
                    .resizable()
            } else {
                LinearGradient(
                    colors: luiModel.configuration.defaultColors, startPoint: .bottom, endPoint: .top
                )
                .overlay(Circle().foregroundColor(.white).padding(iconSize * 0.2))
            }
        }
        .cornerRadius(iconSize * 0.3)
        .frame(width: iconSize, height: iconSize)
        .padding()
    }
}

/// Returns the app version number.
public func getAppVersion() -> String {
    let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    return "\(appVersion ?? "unknown")"
}

private let copyright = """
Introspect for SwiftUI
https://github.com/siteline/SwiftUI-Introspect

Copyright 2019 Timber Software

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the \"Software\"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED \"AS IS\", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

MWKNumberRowInputAccessory
https://github.com/mwkirk/MWKNumberRowInputAccessory

The MIT License (MIT)

Copyright (c) 2016 Mark Kirk

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the \"Software\"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED \"AS IS\", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
"""
