//
//  SpotApiManager.swift
//
//
//  Created by Leon Böttger on 11.12.24.
//

import Foundation
import LUI
import SwiftUI

class SpotApiManager {
    static func spotRequest(apiScope: String, payload: Data) async throws -> Data {
        let isUpload = apiScope.contains("UploadOwner") || apiScope.contains("UploadScans")
        var service = "https://spot-pa.googleapis.com/google.internal.spot.v1.SpotService"

        if isUpload {
            service = "https://spot-pa.googleapis.com/google.internal.spot.v1.SpotReportingService"
        }

        let urlString = "\(service)/\(apiScope)"

        guard let url = URL(string: urlString) else {
            throw NSError(domain: "InvalidURL", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid URL."])
        }

        let headers: [String: String] = try await [
            "User-Agent": "com.google.android.gms/243934009 (Linux; U; Android 9; de_DE; SM-G901F; Build/PQ3A.190801.002; Cronet/129.0.6614.4) grpc-java-cronet/1.68.0-SNAPSHOT",
            "Content-Type": "application/grpc",
            "Te": "trailers",
            "Authorization": "Bearer \(TokenManager.sharedInstance.getSpotToken())",
            "Grpc-Accept-Encoding": "gzip",
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.allHTTPHeaderFields = headers
        request.httpBody = GrpcParser.constructGrpc(payload)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "InvalidResponse", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid response."])
        }

        if httpResponse.statusCode == 200 {
            do {
                return try GrpcParser.extractPayload(data)
            } catch {
                showAlert(title: "Error", message: "There was a server error. Please try again later.")
                throw NSError(domain: "RequestError", code: 0, userInfo: [NSLocalizedDescriptionKey: response])
            }
        } else {
            showAlert(title: "Error", message: "There was a network error. Please try again later.")
            throw NSError(domain: "RequestError", code: 0, userInfo: [NSLocalizedDescriptionKey: response])
        }
    }
}
