//
//  AddInviteView.swift
//  Spot
//
//  Created by Leon Böttger on 01.02.25.
//

import LUI
import SwiftUI

struct AddInviteView: View {
    @Binding var showSheet: Bool

    @State private var loadingInvitation = false
    @State private var currentInvitation: SharingInvitation?
    @State var inviteLink: String = ""

    var body: some View {
        let binding = Binding<Bool> {
            currentInvitation != nil
        } set: { newValue in
            if !newValue {
                currentInvitation = nil
            }
        }

        NavigationSubView {
            BigSymbolViewWithText(symbol: "person.2.fill", subtitle: "If you were invited to share a Find My Device compatible tracker with someone else, insert the sharing link below.", title: "Add Invite") {
                VStack {
                    CustomTextField(text: $inviteLink, placeholder: "Invite Link", textAlignment: .center)
                        .padding(2)
                        .padding(.horizontal)
                        .background(Color.gray.opacity(0.1).cornerRadius(15))
                        .padding()
                        .padding(.horizontal)
                        .padding(.top)

                    ColoredButton(label: "Add Invite", loading: loadingInvitation) {
                        retrieveInvite(url: inviteLink)
                    }
                    .padding(.top)

                    Spacer()

                    LUIButton(action: pasteInviteLink, label: {
                        UnderlineText(label: "Or Paste From Clipboard")
                    })
                }
            }
        }
        .ignoresSafeArea(.keyboard)
        .background(LUILink(destination: ZStack {
            if let invitation = currentInvitation {
                RetrieveInvitationSheet(showSheet: $showSheet, invitation: invitation)
            }
        }, isActive: binding))
    }

    func pasteInviteLink() {
        if let clipboardText = UIPasteboard.general.string {
            doubleVibration()
            retrieveInvite(url: clipboardText)
        } else {
            showAlert(title: "Error", message: "Clipboard is empty or doesn't contain text")
        }
    }

    func retrieveInvite(url: String) {
        if url.isEmpty {
            showAlert(title: "Error", message: "Invite Link is empty")
        } else {
            resolveShortenedURL(url) { result in
                Task {
                    var newUrl = url

                    switch result {
                    case let .success(resolvedURL):
                        newUrl = resolvedURL
                    case .failure:
                        break
                    }

                    do {
                        loadingInvitation = true
                        let sharingInvitation = try await UpdateBleDeviceSharingSettings.retrieveInvitationFromLink(link: newUrl)
                        currentInvitation = sharingInvitation
                    } catch {
                        showAlert(title: "Error", message: "Couldn't retrieve invitation from link: \(error)")
                    }

                    loadingInvitation = false
                }
            }
        }
    }

    func resolveShortenedURL(_ shortURL: String, completion: @escaping (Result<String, Error>) -> Void) {
        guard let url = URL(string: shortURL) else {
            completion(.failure(NSError(domain: "Invalid URL", code: 400, userInfo: nil)))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10 // Set timeout to prevent hanging

        // Use a custom URLSession to capture redirects
        let session = URLSession(configuration: .default, delegate: RedirectHandler(completion: completion), delegateQueue: nil)

        let task = session.dataTask(with: request)
        task.resume()
    }

    /// URLSessionDelegate to handle redirects
    class RedirectHandler: NSObject, URLSessionDelegate, URLSessionTaskDelegate {
        let completion: (Result<String, Error>) -> Void

        init(completion: @escaping (Result<String, Error>) -> Void) {
            self.completion = completion
        }

        /// Handle completion without redirects
        func urlSession(_: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            if let error {
                completion(.failure(error))
            } else if let finalURL = task.currentRequest?.url?.absoluteString {
                completion(.success(finalURL)) // No redirect, return the original URL
            }
        }
    }
}
