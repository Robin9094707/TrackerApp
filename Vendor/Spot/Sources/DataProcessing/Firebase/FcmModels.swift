//
//  FcmModels.swift
//
//
//  Created by Leon Böttger on 07.12.24.
//

import Foundation
import Combine
import SwiftProtobuf

struct FcmRegisterConfig {
    var projectId: String
    var appId: String
    var apiKey: String
    var messagingSenderId: String
    var bundleId: String = "receiver.push.com"
    var chromeId: String = "org.chromium.linux"
    var chromeVersion: String = "94.0.4606.51"
    var vapidKey: String?
    var persistentIds: [String] = []
    var heartbeatIntervalMs: Int = 5 * 60 * 1000 // 5 mins
    var androidPackage: String?
    var androidCertSha1: String?
}

enum ErrorType: Int {
    case connection = 1
    case read = 2
    case login = 3
    case notify = 4
}

struct FcmPush {
    let data: Data
    let persistentId: String
}

class FcmPushClientConfig {
    var serverHeartbeatInterval: TimeInterval = 10
    var clientHeartbeatInterval: TimeInterval = 20
    var sendSelectiveAcknowledgements: Bool = true
    var startSecondsBeforeRetryConnect: Double = 3
    var resetInterval: TimeInterval = 3
    var heartbeatAckTimeout: TimeInterval = 5
    var abortOnSequentialErrorCount: Int = 3
    var logWarnLimit: Int = 5
}

struct MessageWrapper {
    var message: Message
    var type: MCSMessageTag
}

enum MCSMessageTag: Int, CaseIterable {
    case HeartbeatPing = 0
    case HeartbeatAck = 1
    case LoginRequest = 2
    case LoginResponse = 3
    case Close = 4
    // case MessageStanza = 5
    // case PresenceStanza = 6
    case IqStanza = 7
    case DataMessageStanza = 8
    /// case BatchPresenceStanza = 9
    case StreamErrorStanza = 10
    // case HttpRequest = 11
    // case HttpResponse = 12
    // case BindAccountRequest = 13
    // case BindAccountResponse = 14
    // case TalkMetadata = 15

    static func fromInt(_ value: Int) -> MCSMessageTag? {
        if allCases.contains(where: { $0.rawValue == value }) {
            return MCSMessageTag(rawValue: value)
        }
        return nil
    }

    func getInstance(with bytes: Data) -> Message? {
        do {
            switch self {
            case .HeartbeatPing:
                return try McsProto_HeartbeatPing(serializedBytes: bytes)
            case .HeartbeatAck:
                return try McsProto_HeartbeatAck(serializedBytes: bytes)
            case .LoginRequest:
                return try McsProto_LoginRequest(serializedBytes: bytes)
            case .LoginResponse:
                return try McsProto_LoginResponse(serializedBytes: bytes)
            case .Close:
                return try McsProto_Close(serializedBytes: bytes)
            case .DataMessageStanza:
                return try McsProto_DataMessageStanza(serializedBytes: bytes)
            case .StreamErrorStanza:
                return try McsProto_StreamErrorStanza(serializedBytes: bytes)
            case .IqStanza:
                return try McsProto_IqStanza(serializedBytes: bytes)
            }
        } catch {
            return nil
        }
    }
}

struct FcmCredentials: Codable, Equatable {
    struct Config: Codable, Equatable {
        var bundleId: String
        var projectId: String
        var vapidKey: String?
    }

    var keys: FcmKeys
    var gcm: GcmRegistration
    var fcm: FcmRegistrationAndInstallation
    var config: Config
}

struct FcmInstallation: Codable, Equatable {
    struct AuthToken: Codable, Equatable {
        let token: String
        let expiresIn: String
    }

    let authToken: AuthToken
    var refreshToken: String = ""
    var fid: String = ""
}

struct FcmRegistration: Codable, Equatable {
    struct Web: Codable, Equatable {
        var auth: String
        var endpoint: String
        var p256dh: String
    }

    var web: Web
    var name: String
    var token: String
}

struct FcmRegistrationAndInstallation: Codable, Equatable {
    let registration: FcmRegistration
    let installation: FcmInstallation
}

struct FcmKeys: Codable, Equatable {
    var publicKey: String
    var privateKey: String
    var secret: String
}

struct GcmRegistration: Codable, Equatable {
    var token: String
    var app_id: String
    var android_id: UInt64
    var security_token: UInt64
}
