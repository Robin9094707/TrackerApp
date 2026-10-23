//
//  ShareView.swift
//  LUI
//
//  Created by Leon Böttger on 25.02.25.
//

import SwiftUI

public struct ShareButton: View {
    public init(label: String, action: @escaping () async throws -> String) {
        self.label = label
        self.action = action
    }

    let label: String
    let action: () async throws -> String

    public var body: some View {
        SettingsLoadingLabelAsync(imageName: "square.and.arrow.up", text: label, backgroundColor: .blue) {
            let sharingLink = try await action()
            bringUpShareSheet(text: sharingLink)
        }
    }
}

private func bringUpShareSheet(text: String) {
    let shareActivity = UIActivityViewController(activityItems: [text], applicationActivities: nil)

    if let vc = UIApplication.shared.windows.first?.rootViewController {
        shareActivity.popoverPresentationController?.sourceView = vc.view
        shareActivity.popoverPresentationController?.permittedArrowDirections =
            UIPopoverArrowDirection.down

        vc.present(
            shareActivity, animated: true,
            completion: {}
        )
    }
}

public struct SettingsLoadingLabel: View {
    public init(
        imageName: String, text: String, backgroundColor: Color, isLoading: Bool,
        action: @escaping () -> Void
    ) {
        self.imageName = imageName
        self.text = text
        self.backgroundColor = backgroundColor
        self.isLoading = isLoading
        self.action = action
    }

    let imageName: String
    let text: String
    let backgroundColor: Color
    let isLoading: Bool
    let action: () -> Void

    public var body: some View {
        LUIButton {
            action()
        } label: {
            NavigationLinkLabel(
                imageName: imageName, text: text, backgroundColor: backgroundColor, isLoading: isLoading
            )
        }
    }
}

public struct SettingsLoadingLabelAsync: View {
    public init(
        imageName: String, text: String, backgroundColor: Color,
        action: @escaping () async throws -> Void
    ) {
        self.imageName = imageName
        self.text = text
        self.backgroundColor = backgroundColor
        self.action = action
    }

    let imageName: String
    let text: String
    let backgroundColor: Color
    let action: () async throws -> Void

    @State private var isLoading = false

    public var body: some View {
        let action = {
            isLoading = true
            Task {
                do {
                    try await self.action()
                } catch {}
                isLoading = false
            }
        }

        SettingsLoadingLabel(
            imageName: imageName, text: text, backgroundColor: backgroundColor, isLoading: isLoading,
            action: action
        )
    }
}
