//
//  NovaApiManager.swift
//  Spot
//
//  Created by Leon Böttger on 05.12.24.
//

import Foundation
import Combine

final class NovaApiManager: SharedInstance {
    static var sharedInstance = NovaApiManager()

    /// Scope for executing actions
    private let NOVA_ACTION_API_SCOPE = "nbe_execute_action"

    /// Scope for executing actions
    private let NOVA_LIST_DEVICS_API_SCOPE = "nbe_list_devices"

    /// Queue for fetching devices
    private let deviceFetchQueue = DispatchQueue(label: "com.leonboettger.spot.devicefetchqueue")

    func requestDeviceList() async throws -> DevicesList {
        let result = try await novaRequest(apiScope: NOVA_LIST_DEVICS_API_SCOPE, payload: DeviceListRequest().payload)
        return try DevicesList(serializedBytes: result)
    }

    func controlSoundForDevice(canonicDeviceId: String, action: SoundRequestAction) async throws {
        guard let fcmToken = PushReceiver.sharedInstance.getToken() else {
            throw NSError(domain: "SpotGoogle", code: 2, userInfo: [NSLocalizedDescriptionKey: "Google-Verbindung fehlt. Bitte erneut anmelden."])
        }

        _ = try await novaRequest(apiScope: NOVA_ACTION_API_SCOPE, payload: SoundRequest.create(action: action, canonicDeviceId: canonicDeviceId, gcmRegistrationId: fcmToken))
    }

    func requestLocationDataForDevice(device: LocalFindMyDevice, tryingAgain: Bool = false, callback: @escaping (Bool) -> Void) {
        let requestDate = Date()

        deviceFetchQueue.async {
            let canonicDeviceId = device.canonicDeviceId

            let requestUuid = getRandomUUID()
            guard let fcmToken = PushReceiver.sharedInstance.getToken() else {
                callback(false)
                return
            }

            let isAllAreas = (tryingAgain ? ContributorType.AtAllAreas : Settings.sharedInstance.contributorType) == .AtAllAreas

            let onPushReceiverReady: () -> Void = { [self] in
                Task {
                    do {
                        let payload = LocationRequest(canonicDeviceId: canonicDeviceId, fcmRegistrationId: fcmToken, requestUUID: requestUuid, atAllAreas: isAllAreas).payload
                        _ = try await novaRequest(apiScope: NOVA_ACTION_API_SCOPE, payload: payload)
                    } catch {
                        callback(false)
                    }
                }
            }

            PushReceiver.sharedInstance.registerForMessageUpdates(isListening: onPushReceiverReady) { push in
                // Check if the push is for the current request

                guard let push else {
                    callback(false)
                    return false
                }

                guard device.belongsToCurrentAccount else { return true }
                if let deviceUpdate = self.decodeFcmPayload(payload: push.data), deviceUpdate.fcmMetadata.requestUuid == requestUuid {
                    self.deviceFetchQueue.async {
                        let contributor: ContributorType = isAllAreas ? .AtAllAreas : .HighTrafficOnly

                        let didReceiveUpdate = mergeDeviceUpdate(requestDate: requestDate, contributorType: contributor, deviceUpdateProtobuf: deviceUpdate, localDevice: device)

                        GoogleReportArchive.store(deviceUpdate)
                        callback(true)
                    }

                    return false // Keep listening for all later packets in this request window.
                }

                return false
            }
        }
    }

    private func novaRequest(apiScope: String, payload: Data, failedAttempts: Int = 0) async throws -> Data {
        let url = URL(string: "https://android.googleapis.com/nova/" + apiScope)!
        let androidDeviceManagerOauthToken = try await TokenManager.sharedInstance.getAdmToken()

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer " + androidDeviceManagerOauthToken, forHTTPHeaderField: "Authorization")
        request.setValue("en-US", forHTTPHeaderField: "Accept-Language")
        request.setValue("fmd/20006320; gzip", forHTTPHeaderField: "User-Agent")

        request.httpBody = payload

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "Invalid response", code: 2, userInfo: nil)
        }

        let statusCode = httpResponse.statusCode

        guard (200..<300).contains(statusCode) else {
            if [401, 403].contains(statusCode), failedAttempts == 0 {
                TokenManager.sharedInstance.clearCachedTokens()
                return try await novaRequest(apiScope: apiScope, payload: payload, failedAttempts: 1)
            }
            if [429, 500, 502, 503, 504].contains(statusCode), failedAttempts < 2 {
                try await Task.sleep(nanoseconds: UInt64(failedAttempts + 1) * 1_000_000_000)
                return try await novaRequest(apiScope: apiScope, payload: payload, failedAttempts: failedAttempts + 1)
            }
            throw NSError(domain: "SpotGoogle", code: statusCode, userInfo: [NSLocalizedDescriptionKey:
                "Google-Anfrage fehlgeschlagen (HTTP \(statusCode)). Bitte Verbindung und Anmeldung prüfen."])
        }

        return data
    }

    private func decodeFcmPayload(payload: Data) -> DeviceUpdate? {
        // Interpret obj as JSON
        guard let jsonObject = try? JSONSerialization.jsonObject(with: payload, options: []),
              let jsonDict = jsonObject as? [String: Any]
        else {
            return nil
        }

        // Check if the payload is present
        if let data = jsonDict["data"] as? [String: Any], let base64String = data["com.google.android.apps.adm.FCM_PAYLOAD"] as? String {
            // Decode the base64 string
            if let decodedData = Data(base64Encoded: base64String) {
                do {
                    return try DeviceUpdate(serializedBytes: decodedData)
                } catch {}
            }
        } else {}

        return nil
    }
}
