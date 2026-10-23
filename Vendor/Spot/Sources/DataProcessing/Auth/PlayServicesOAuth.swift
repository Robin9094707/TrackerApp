//
//  PlayServicesOAuth.swift
//  Spot
//
//  Created by Leon Böttger on 05.12.24.
//

import CommonCrypto
import Foundation

class PlayServicesOAuth {
    /// Perform an OAuth token exchange
    static func requestAASToken(
        email: String,
        oauthToken: String,
        androidID: String,
        completion: @escaping (Result<[String: String], Error>) -> Void
    ) {
        let data: [String: Any] = [
            "accountType": "HOSTED_OR_GOOGLE",
            "Email": email,
            "has_permission": 1,
            "add_account": 1,
            "ACCESS_TOKEN": 1,
            "Token": oauthToken,
            "service": "ac2dm",
            "source": "android",
            "androidId": androidID,
            "device_country": "us",
            "operatorCountry": "us",
            "lang": "en",
            "sdk_version": 17,
            "client_sig": "38918a453d07199354f8b19af05ec6562ced5788",
            "callerSig": "38918a453d07199354f8b19af05ec6562ced5788",
            "droidguard_results": "dummy123",
        ]

        performAuthRequest(data: data, completion: completion)
    }

    /// Perform an OAuth token exchange
    static func performOauth(
        email: String,
        aasToken: String,
        androidID: String,
        service: String,
        app: String,
        completion: @escaping (Result<[String: String], Error>) -> Void
    ) {
        let data: [String: Any] = [
            "accountType": "HOSTED_OR_GOOGLE",
            "Email": email,
            "has_permission": 1,
            "EncryptedPasswd": aasToken,
            "service": service,
            "source": "android",
            "androidId": androidID,
            "app": app,
            "client_sig": "38918a453d07199354f8b19af05ec6562ced5788",
            "device_country": "us",
            "operatorCountry": "us",
            "lang": "en",
            "sdk_version": 17,
        ]

        performAuthRequest(data: data, completion: completion)
    }

    /// Perform a generic auth request
    private static func performAuthRequest(
        data: [String: Any],
        completion: @escaping (Result<[String: String], Error>) -> Void
    ) {
        guard let url = URL(string: "https://android.clients.google.com/auth") else {
            completion(.failure(NSError(domain: "Invalid URL", code: 1, userInfo: nil)))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("GoogleAuth/1.4", forHTTPHeaderField: "User-Agent")

        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        request.httpBody = data.map { key, value in
            let encodedKey = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
            let encodedValue = String(describing: value).addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
            return "\(encodedKey)=\(encodedValue)"
        }.joined(separator: "&").data(using: .utf8)

        let task = URLSession.shared.dataTask(with: request) { data, _, error in
            if let error {
                completion(.failure(error))
                return
            }

            guard let data, let responseText = String(data: data, encoding: .utf8) else {
                completion(.failure(NSError(domain: "Invalid response", code: 2, userInfo: nil)))
                return
            }

            // Parse the response text into a dictionary
            let parsedResponse = parseAuthResponse(responseText)
            completion(.success(parsedResponse))
        }

        task.resume()
    }

    /// Parse the authentication response
    private static func parseAuthResponse(_ text: String) -> [String: String] {
        var responseData: [String: String] = [:]

        let lines = text.split(separator: "\n")
        for line in lines {
            let parts = line.split(separator: "=", maxSplits: 1)
            if parts.count == 2 {
                let key = String(parts[0])
                let value = String(parts[1])
                responseData[key] = value
            }
        }

        return responseData
    }
}
