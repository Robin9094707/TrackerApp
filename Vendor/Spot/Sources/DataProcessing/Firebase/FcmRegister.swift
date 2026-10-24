//
//  FcmRegister.swift
//
//
//  Created by Leon Böttger on 05.12.24.
//

import CryptoKit
import Foundation
import Combine
import SwiftUI

class FcmRegister {
    private let clientTimeout: TimeInterval = 3.0
    private var config: FcmRegisterConfig
    private var credentials: FcmCredentials?
    private var credentialsUpdatedCallback: ((FcmCredentials) -> Void)?
    private var session: URLSession

    init(config: FcmRegisterConfig, credentials: FcmCredentials?) {
        self.config = config
        self.credentials = credentials

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 15
        session = URLSession(configuration: configuration)
    }

    func checkinOrRegister() async throws -> FcmCredentials {
        if let credentials {
            if let _ = try await gcmCheckIn(androidId: credentials.gcm.android_id, securityToken: credentials.gcm.security_token) {
                return credentials
            }
        }

        credentials = try await register()
        guard let credentials else {
            throw NSError(domain: "Unable to register with fcm", code: 0, userInfo: nil)
        }

        return credentials
    }

    func close() {
        session.invalidateAndCancel()
    }

    private func register() async throws -> FcmCredentials {
        guard let gcmData = try await gcmCheckInAndRegister() else {
            throw NSError(domain: "Unable to establish subscription with Google Cloud Messaging.", code: 0, userInfo: nil)
        }

        let keys = try generateKeys()

        guard let fcmData = try await fcmInstallAndRegister(gcmData: gcmData, keys: keys) else {
            throw NSError(domain: "Unable to register with fcm", code: 0, userInfo: nil)
        }

        return FcmCredentials(keys: keys, gcm: gcmData, fcm: fcmData, config: FcmCredentials.Config(bundleId: config.bundleId, projectId: config.projectId, vapidKey: config.vapidKey))
    }

    private func generateKeys() throws -> FcmKeys {
        let privateKey = P256.Signing.PrivateKey()
        let publicKey = privateKey.publicKey

        let serializedPrivate = dataToBase64URL(privateKey.derRepresentation)
        let serializedPublic = dataToBase64URL(Data([4]) + publicKey.rawRepresentation)

        return try FcmKeys(publicKey: serializedPublic, privateKey: serializedPrivate, secret: dataToBase64URL(SecureRandom.getBytes(16)))
    }

    /// __ GCM __

    private func gcmCheckInAndRegister() async throws -> GcmRegistration? {
        guard let options = try await gcmCheckIn() else {
            throw NSError(domain: "Unable to register and check in to gcm", code: 0, userInfo: nil)
        }
        return try await gcmRegister(options: options)
    }

    private func gcmCheckIn(androidId: UInt64? = nil, securityToken: UInt64? = nil) async throws -> CheckinProto_AndroidCheckinResponse? {
        var payload = getCheckinPayload(androidId: androidId, securityToken: securityToken)
        let retries = 3
        var checkinResponse: CheckinProto_AndroidCheckinResponse?
        var content: Data?

        for _ in 0 ..< retries {
            do {
                let GCM_CHECKIN_URL = "https://android.clients.google.com/checkin"
                var request = URLRequest(url: URL(string: GCM_CHECKIN_URL)!)
                request.httpMethod = "POST"
                request.setValue("application/x-protobuf", forHTTPHeaderField: "Content-Type")
                request.httpBody = try payload.serializedData()

                let (data, response) = try await fetchDataSynchronously(with: request)
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    checkinResponse = try CheckinProto_AndroidCheckinResponse(serializedBytes: data)
                    content = data
                    break
                } else {
                    let text = String(data: data, encoding: .utf8)
                    if checkinResponse != nil, content != nil {
                        break
                    } else {}
                    payload = getCheckinPayload()
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                }
            } catch {
                try await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }

        if checkinResponse == nil || content == nil {
            return nil
        }

        return checkinResponse
    }

    private func getCheckinPayload(androidId: UInt64? = nil, securityToken: UInt64? = nil) -> CheckinProto_AndroidCheckinRequest {
        var chrome = CheckinProto_ChromeBuildProto()
        chrome.platform = .linux
        chrome.chromeVersion = config.chromeVersion
        chrome.channel = .stable

        var checkin = CheckinProto_AndroidCheckinProto()
        checkin.type = .deviceChromeBrowser
        checkin.chromeBuild = chrome

        var payload = CheckinProto_AndroidCheckinRequest()
        payload.userSerialNumber = 0
        payload.checkin = checkin
        payload.version = 3

        if let androidId, let securityToken {
            payload.id = Int64(androidId)
            payload.securityToken = UInt64(securityToken)
        }

        return payload
    }

    private func gcmRegister(options: CheckinProto_AndroidCheckinResponse, retries: Int = 3) async throws -> GcmRegistration? {
        let gcmAppId = "wp:\(config.bundleId)#\(getRandomUUID())"
        guard options.hasAndroidID, options.hasSecurityToken else {
            return nil
        }

        let androidId = options.androidID
        let securityToken = options.securityToken
        let GCM_SERVER_KEY_B64 = "BDOU99-h67HcA6JeFXHbSNMu7e2yNNu3RzoMj8TM4W88jITfq7ZmPvIM1Iv-4_l2LxQcYwhqby2xGpWwzjfAnG4"

        let headers = [
            "Authorization": "AidLogin \(androidId):\(securityToken)",
            "Content-Type": "application/x-www-form-urlencoded",
        ]
        let body = [
            "app": "org.chromium.linux",
            "X-subtype": gcmAppId,
            "device": "\(androidId)",
            "sender": GCM_SERVER_KEY_B64,
        ]

        // Create the body data
        guard let bodyData = createFormURLEncodedBody(from: body) else {
            return nil
        }

        var lastError: Error?
        for _ in 0 ..< retries {
            do {
                let GCM_REGISTER_URL = "https://android.clients.google.com/c2dm/register3"
                var request = URLRequest(url: URL(string: GCM_REGISTER_URL)!)
                request.httpMethod = "POST"
                request.allHTTPHeaderFields = headers
                request.httpBody = bodyData

                let (data, response) = try await fetchDataSynchronously(with: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
                let responseText = String(data: data, encoding: .utf8)

                if responseText?.contains("Error") == true {
                    lastError = NSError(domain: responseText ?? "", code: 0, userInfo: nil)
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                    continue
                }

                guard let responseText, responseText.hasPrefix("token="), responseText.count > 6 else { throw URLError(.badServerResponse) }
                let token = String(responseText.dropFirst(6)).trimmingCharacters(in: .whitespacesAndNewlines)
                return GcmRegistration(token: token, app_id: gcmAppId, android_id: androidId, security_token: securityToken)
            } catch {
                lastError = error

                try await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }

        if let lastError {
            throw lastError
        } else {
            throw NSError(domain: "Unable to complete gcm auth request after \(retries) tries", code: 0, userInfo: nil)
        }
    }

    /// __ FCM __

    private func fcmInstallAndRegister(gcmData: GcmRegistration, keys: FcmKeys) async throws -> FcmRegistrationAndInstallation? {
        if let installation = try await fcmInstall(), let registration = try await fcmRegister(gcmData: gcmData, installation: installation, keys: keys) {
            return FcmRegistrationAndInstallation(registration: registration, installation: installation)
        }
        return nil
    }

    private func addAndroidRestrictionHeaders(to headers: inout [String: String]) throws {
        guard let androidPackage = config.androidPackage, !androidPackage.isEmpty,
              let androidCertSha1 = config.androidCertSha1, !androidCertSha1.isEmpty else { return }

        let fingerprint = androidCertSha1
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: " ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard fingerprint.count == 40,
              fingerprint.utf8.allSatisfy({ (48 ... 57).contains($0) || (97 ... 102).contains($0) })
        else {
            throw NSError(domain: "InvalidSHA1Fingerprint", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid SHA-1 fingerprint."])
        }

        headers["X-Android-Package"] = androidPackage
        headers["X-Android-Cert"] = fingerprint
    }

    private func fcmInstall() async throws -> FcmInstallation? {
        var fid = try SecureRandom.getBytes(17)
        fid[0] = 0b0111_0000 + (fid[0] % 0b0001_0000)
        let fid64 = fid.base64EncodedString()

        let hbHeader = FcmRegister.getHbHeader()
        var headers = [
            "Content-Type": "application/json",
            "x-firebase-client": hbHeader,
            "x-goog-api-key": config.apiKey,
        ]
        try addAndroidRestrictionHeaders(to: &headers)
        let payload = [
            "appId": config.appId,
            "authVersion": "FIS_v2",
            "fid": fid64,
            "sdkVersion": "w:0.6.6",
        ]

        let url = "https://firebaseinstallations.googleapis.com/v1/projects/\(config.projectId)/installations"
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = "POST"
        request.allHTTPHeaderFields = headers
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: .withoutEscapingSlashes)

        let (data, response) = try await fetchDataSynchronously(with: request)

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
            return try JSONDecoder().decode(FcmInstallation.self, from: data)

        } else {
            let text = String(data: data, encoding: .utf8)

            return nil
        }
    }

    static func getHbHeader() -> String {
        do {
            let data = HeartbeatData(heartbeats: [], version: 2)
            return try JSONEncoder().encode(data).base64EncodedString()
        } catch {}

        return ""
    }

    private struct HeartbeatData: Codable {
        let heartbeats: [String]
        let version: Int
    }

    private func fcmRegister(gcmData: GcmRegistration, installation: FcmInstallation, keys: FcmKeys, retries: Int = 3) async throws -> FcmRegistration? {
        var headers = [
            "Content-Type": "application/json",
            "x-goog-api-key": config.apiKey,
            "x-goog-firebase-installations-auth": installation.authToken.token,
        ]
        try addAndroidRestrictionHeaders(to: &headers)
        let vapidKey = config.vapidKey

        let payload = [
            "web": [
                "applicationPubKey": vapidKey ?? "",
                "auth": keys.secret,
                "endpoint": "https://fcm.googleapis.com/fcm/send/\(gcmData.token)",
                "p256dh": keys.publicKey,
            ],
        ]

        let url = "https://fcmregistrations.googleapis.com/v1/projects/\(config.projectId)/registrations"
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = "POST"
        request.allHTTPHeaderFields = headers
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        for _ in 0 ..< retries {
            do {
                let (data, response) = try await fetchDataSynchronously(with: request)
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    return try JSONDecoder().decode(FcmRegistration.self, from: data)
                } else {
                    let text = String(data: data, encoding: .utf8)
                }
            } catch {
                try await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }

        return nil
    }

    /// __ Helper functions __

    private func fetchDataSynchronously(with request: URLRequest) async throws -> (Data, URLResponse) {
        try Task.checkCancellation()
        return try await session.data(for: request)
    }

    /// Encode parameters into x-www-form-urlencoded format
    private func createFormURLEncodedBody(from parameters: [String: String]) -> Data? {
        var components: [String] = []

        // Iterate over parameters and encode keys and values
        for (key, value) in parameters {
            if let encodedKey = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
               let encodedValue = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
            {
                components.append("\(encodedKey)=\(encodedValue)")
            }
        }

        // Join all components with & and return data
        let bodyString = components.joined(separator: "&")
        return bodyString.data(using: .utf8)
    }
}
