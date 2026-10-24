//
//  TokenManager.swift
//
//
//  Created by Leon Böttger on 05.12.24.
//

import Dispatch
import Foundation
import Combine

final class TokenManager: SharedInstance {
    static var sharedInstance = TokenManager()

    private var admToken: CachedToken?
    private var spotToken: CachedToken?

    @SyncStorage(key: DeviceOnlyKeys.username, defaultValue: nil, on: TokenManager.self, ud: UserDefaults(suiteName: "eu.rjuhas.rjtracker.spot")!) var username: String?
    @KeychainStorage(key: .aasToken, on: TokenManager.self) var aasToken: String?
    @KeychainStorage(key: .ownerKey, on: TokenManager.self) var ownerKey: String?
    @SyncStorage(key: DeviceOnlyKeys.ownerKeyVersion, defaultValue: 1, on: TokenManager.self, ud: UserDefaults(suiteName: "eu.rjuhas.rjtracker.spot")!) var ownerKeyVersion: Int
    @KeychainStorage(key: .sharedKey, on: TokenManager.self) var sharedKey: String?

    func getAdmToken() async throws -> String {
        if let token = admToken, !token.expirationDate.isInPast {
            return token.token
        }

        let account = username, identity = aasToken
        let newToken = try await requestToken(scope: "android_device_manager")
        guard username == account, aasToken == identity else { throw CancellationError() }
        admToken = newToken

        return newToken.token
    }

    func getSpotToken() async throws -> String {
        if let token = spotToken, !token.expirationDate.isInPast {
            return token.token
        }

        let account = username, identity = aasToken
        let newToken = try await requestToken(scope: "spot", playServices: true)
        guard username == account, aasToken == identity else { throw CancellationError() }
        spotToken = newToken

        return newToken.token
    }

    func getLoginCookies() async throws -> [WebloginAuthResponse.WebloginCookies.Cookie] {
        let token = try await requestToken(scope: "weblogin", playServices: true)
        let asData = base64UrlToData(base64UrlString: token.token)

        guard let asData else {
            throw NSError(domain: "TokenManagerError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Could not convert Cookie response to data."])
        }

        let asProtobuf = try WebloginAuthResponse(serializedBytes: asData)

        return asProtobuf.webloginCookies.cookies
    }

    private func requestToken(scope: String, playServices: Bool = false) async throws -> CachedToken {
        guard let username, let aasToken else {

            throw NSError(domain: "TokenManagerError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Username or AAS token is missing."])
        }

        guard let androidId = PushReceiver.sharedInstance.getAndroidId()?.description else {
            let errorMessage = "Android ID is missing."


            throw NSError(domain: "TokenManagerError", code: 0, userInfo: [NSLocalizedDescriptionKey: errorMessage])
        }

        let requestApp = playServices ? "com.google.android.gms" : "com.google.android.apps.adm"

        var serviceScope = if scope == "weblogin" {
            "weblogin:url=https://accounts.google.com"
        } else {
            "oauth2:https://www.googleapis.com/auth/\(scope)"
        }

        return try await withCheckedThrowingContinuation { continuation in
            PlayServicesOAuth.performOauth(
                email: username,
                aasToken: aasToken,
                androidID: androidId,
                service: serviceScope,
                app: requestApp
            ) { result in
                switch result {
                case let .success(authResponse):
                    if let auth = authResponse["Auth"] {
                        let duration = Double(authResponse["ExpiresInDurationSec"] ?? "")
                        let absolute = Double(authResponse["Expiry"] ?? "")
                        let expiry = duration.map { Date().addingTimeInterval($0) }
                            ?? absolute.map { Date(timeIntervalSince1970: $0) }
                            ?? Date().addingTimeInterval(1800)
                        let expirationDate = expiry.addingTimeInterval(-60)
                        continuation.resume(returning: CachedToken(token: auth, expirationDate: expirationDate))
                    } else {
                        continuation.resume(throwing: NSError(domain: "TokenManagerError", code: 0, userInfo: [NSLocalizedDescriptionKey: "No auth token found in response."]))
                    }
                case let .failure(error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func clearCachedTokens() {
        admToken = nil
        spotToken = nil
    }

    func deleteTokens() {
        clearCachedTokens()
        username = nil
        aasToken = nil
        ownerKey = nil
        sharedKey = nil

        // also re-register Firebase token
        PushReceiver.sharedInstance.signOut()

        // clear WKWebView cache, if user was still signed in
        CookieCache.clearWKWebViewCacheAndCookies {}
    }
}
