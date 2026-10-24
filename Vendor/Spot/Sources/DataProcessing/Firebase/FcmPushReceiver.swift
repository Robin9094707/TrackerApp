//
//  FcmPushReceiver.swift
//
//
//  Created by Leon Böttger on 06.12.24.
//

import CryptoKit
import Foundation
import Combine
import Network
import SwiftProtobuf
#if canImport(UIKit)
    import UIKit
#endif

final class PushReceiver: SharedInstance {
    static var sharedInstance: PushReceiver = .init()

    private let MCS_VERSION: UInt8 = 41

    private var newMessageCallbacks = [MessageCallback]()
    private var fcmConfig: FcmRegisterConfig
    private let credentialLock = NSLock()
    private var storedCredentials: FcmCredentials?
    private var credentials: FcmCredentials? {
        get { credentialLock.lock(); defer { credentialLock.unlock() }; return storedCredentials }
        set { credentialLock.lock(); storedCredentials = newValue; credentialLock.unlock() }
    }
    @MainActor private var registrationTask: Task<FcmCredentials, Error>?
    private var connectionGeneration = UUID()
    private var ready = false
    private var readyCallbacks: [() -> Void] = []
    private var persistentIds = [String]()
    private var config: FcmPushClientConfig
    private var doListen: Bool = false
    private var sequentialErrorCounters: [ErrorType: Int] = [:]
    private var inputStreamId: Int32 = 0
    private var lastInputStreamIdReported: Int32 = -1
    private var lastLoginTime = Date.distantPast
    private var lastMessageTime = Date.distantPast
    private var firstMessage = true
    private var registerer: FcmRegister?

    private var buffer = Data()
    private var bufferIndex = 0
    private var connection: NWConnection?

    private var heartbeatTimer: Timer?
    private let pushQueue = DispatchQueue(label: "com.leonboettger.spot.pushqueue")
    private let networkQueue = DispatchQueue(label: "com.leonboettger.spot.networkqueue")

    private init() {
        fcmConfig = FcmRegisterConfig(
            projectId: "google.com:api-project-289722593072",
            appId: "1:289722593072:android:3cfcf5bc359f0308",
            apiKey: "AIzaSyD_gko3P392v6how2H7UpdeXQ0v2HLettc",
            messagingSenderId: "289722593072",
            bundleId: "com.google.android.apps.adm",
            androidPackage: "com.google.android.apps.adm",
            androidCertSha1: "38918a453d07199354f8b19af05ec6562ced5788"
        )

        config = FcmPushClientConfig()
        do {
            credentials = try KeychainStore.shared.load(FcmCredentials.self, for: .fcmCredentials)
        } catch {
            showAlert(title: "Secure Storage Error", message: error.localizedDescription)
        }
    }

    /// PUBLIC API

    func getToken() -> String? {
        credentials?.fcm.registration.token
    }

    func getAndroidId() -> UInt64? {
        credentials?.gcm.android_id
    }

    func registerForMessageUpdates(isListening: @escaping () -> Void, callback: @escaping (FcmPush?) -> Bool) {
        pushQueue.async { [self] in
            let newCallback = MessageCallback(callback: callback)
            newMessageCallbacks.append(newCallback)

            guard credentials != nil else { callback(nil); newMessageCallbacks.removeAll { $0 == newCallback }; return }
            if ready { isListening() } else { readyCallbacks.append(isListening) }
            if !doListen { start() }

            pushQueue.asyncAfter(deadline: .now() + 35) { [self] in
                if newMessageCallbacks.contains(newCallback) {
                    newMessageCallbacks.removeAll { $0 == newCallback }
                    _ = callback(nil)
                }

                if newMessageCallbacks.isEmpty {
                    stop()
                }
            }
        }
    }

    @MainActor func prepare(force: Bool = false) async throws {
        if !force, getToken() != nil, getAndroidId() != nil { return }
        if let registrationTask { _ = try await registrationTask.value; return }
        let existing = credentials
        let register = FcmRegister(config: fcmConfig, credentials: existing)
        let task = Task { () throws -> FcmCredentials in
            defer { register.close() }
            return try await register.checkinOrRegister()
        }
        registrationTask = task
        defer { registrationTask = nil }
        do {
            let result: FcmCredentials = try await googleCallback(seconds: 30) { done in
                Task { do { done(.success(try await task.value)) } catch { done(.failure(error)) } }
            }
            try storeCredentials(credentials: result)
        } catch {
            task.cancel(); register.close()
            // An offline device must retain its already working Google identity.
            throw error
        }
    }

    func signOut() {
        pushQueue.async {
            self.stop()
            self.newMessageCallbacks.removeAll()
            do {
                try self.removeCredentials()
            } catch {
                showAlert(title: "Secure Storage Error", message: error.localizedDescription)
            }
        }
    }

    /// CONNECTION SETUP

    private func start() {
        // Connect to FCM and start listening for push notifications.
        doListen = true
        listen()
        startHeartbeatTimer()
    }

    private func storeCredentials(credentials: FcmCredentials?) throws {
        if let credentials {
            do {
                try KeychainStore.shared.save(credentials, for: .fcmCredentials)
            } catch {
                showAlert(title: "Secure Storage Error", message: error.localizedDescription)
                throw error
            }
            self.credentials = credentials
        }
    }

    private func removeCredentials() throws {
        try KeychainStore.shared.remove(for: .fcmCredentials)
        credentials = nil
    }

    private func listen() {
        let generation = UUID()
        connectionGeneration = generation
        let connection = NWConnection(host: "mtalk.google.com", port: 5228, using: .tls)
        self.connection = connection
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self, let connection else { return }
            self.pushQueue.async {
                guard self.connectionGeneration == generation, self.doListen else { return }
                switch state {
                case .ready:
                    self.login(); self.startReading()
                case .failed, .cancelled:
                    self.reset()
                default: break
                }
            }
        }
        connection.start(queue: networkQueue)
        pushQueue.asyncAfter(deadline: .now() + 12) { [weak self] in
            guard let self, self.connectionGeneration == generation, !self.ready else { return }
            self.failPending()
            showAlert(title: "Google-Push", message: "Google-Push hat nicht rechtzeitig geantwortet. Die Anmeldung und vorhandene Reports bleiben erhalten; erneut versuchen.")
            self.stop()
        }
    }

    /// USER AUTHENTIFICATION

    private func login() {
        inputStreamId = 0
        lastInputStreamIdReported = -1
        firstMessage = true
        lastLoginTime = .now

        guard let androidId = credentials?.gcm.android_id, let credentials else { return }

        var req = McsProto_LoginRequest()
        req.adaptiveHeartbeat = false
        req.authService = .androidID
        req.authToken = String(credentials.gcm.security_token)
        req.id = fcmConfig.chromeVersion
        req.domain = "mcs.android.com"
        req.deviceID = "android-\(intToHex(Int(androidId)))"
        req.networkType = 1
        req.resource = String(androidId)
        req.user = String(androidId)
        req.useRmq2 = true

        var setting = McsProto_Setting()
        setting.name = "new_vc"
        setting.value = "1"

        req.setting.append(setting)
        req.receivedPersistentID.append(contentsOf: persistentIds)
        req.heartbeatStat.ip = ""
        req.heartbeatStat.timeout = true
        req.heartbeatStat.intervalMs = Int32(1000 * config.serverHeartbeatInterval)

        sendMsg(messageWrapper: MessageWrapper(message: req, type: .LoginRequest))
    }

    /// BUFFER
    private func startReading() {
        guard let connection else {
            return
        }

        if !doListen {
            return
        }

        let generation = connectionGeneration
        var connectionInvalid = false

        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
            self.pushQueue.async {
                if connectionInvalid || !self.doListen || self.connectionGeneration != generation {
                    return
                }

                if let data {
                    self.buffer.append(data)

                    do {
                        try self.checkForMessages()
                    } catch {
                        self.buffer = Data(); self.reset()
                    }
                }

                if isComplete {
                    connectionInvalid = true
                    self.connection?.forceCancel()
                    self.connection = nil
                    self.reset()
                } else if let error {
                    connectionInvalid = true

                    self.connection?.forceCancel()
                    self.connection = nil
                    self.reset()
                } else {
                    // One read done, start another
                    self.startReading()
                }
            }
        }
    }

    private var frameDecoder = GoogleMCSDecoder()
    private func checkForMessages() throws {
        let frames = try frameDecoder.append(buffer)
        buffer.removeAll(keepingCapacity: true)
        for frame in frames {
            firstMessage = false
            if let type = MCSMessageTag.fromInt(Int(frame.tag)), let message = type.getInstance(with: frame.payload) {
                handleMessage(msg: MessageWrapper(message: message, type: type))
            }
        }
    }

    private func sendMsg(messageWrapper: MessageWrapper) {
        let buf = makePacket(messageWrapper: messageWrapper, includeVersion: firstMessage)

        if let connection, let buf {
            connection.send(content: buf, completion: .contentProcessed { error in
                if let error {}
            })
        }
    }

    private func encodeVarint32(_ x: Int) -> Data {
        if x == 0 {
            return Data([0])
        }

        var res = Data()
        var value = x
        while value != 0 {
            var byte = UInt8(value & 0x7F)
            value >>= 7
            if value != 0 {
                byte |= 0x80
            }
            res.append(byte)
        }
        return res
    }

    private func makePacket(messageWrapper: MessageWrapper, includeVersion: Bool) -> Data? {
        let tag = UInt8(messageWrapper.type.rawValue)

        let header = includeVersion ? Data([MCS_VERSION, tag]) : Data([tag])

        do {
            let payload = try messageWrapper.message.serializedData()
            return header + encodeVarint32(payload.count) + payload
        } catch {}

        return nil
    }

    /// HEARTBEATS

    private func startHeartbeatTimer() {
        // Run timer on main thread to avoid issues with backgrounding
        DispatchQueue.main.async {
            self.heartbeatTimer?.invalidate()
            self.heartbeatTimer = Timer.scheduledTimer(withTimeInterval: self.config.clientHeartbeatInterval, repeats: true) { [self] _ in
                pushQueue.async { [self] in
                    sendHeartbeat()

                    pushQueue.asyncAfter(deadline: .now() + config.heartbeatAckTimeout) { [self] in
                        if lastMessageTime.addingTimeInterval(config.clientHeartbeatInterval) < .now, doListen {
                            reset()
                        }
                    }
                }
            }
        }
    }

    private func sendHeartbeat() {
        var req = McsProto_HeartbeatPing()

        if newInputStreamIdAvailable() {
            req.lastStreamIDReceived = getInputStreamId()
        }

        sendMsg(messageWrapper: MessageWrapper(message: req, type: .HeartbeatPing))
    }

    private func sendSelectiveAck(_ persistentId: String) {
        var iqStanza = McsProto_IqStanza()
        iqStanza.type = .set
        iqStanza.id = ""
        let MCS_SELECTIVE_ACK_ID: Int32 = 12
        iqStanza.extension.id = MCS_SELECTIVE_ACK_ID

        var selectiveAck = McsProto_SelectiveAck()
        selectiveAck.id.append(persistentId)

        do {
            iqStanza.extension.data = try selectiveAck.serializedData()

            sendMsg(messageWrapper: MessageWrapper(message: iqStanza, type: .IqStanza))
        } catch {}
    }

    /// MESSAGE HANDLERS

    private func handleMessage(msg: MessageWrapper) {
        lastMessageTime = .now
        inputStreamId += 1

        if msg.type == .Close {
            if tryIncrementErrorCount(errorType: .connection) {
                reset()
            }
            return
        }

        if msg.type == .LoginResponse, let loginResponse = msg.message as? McsProto_LoginResponse {
            if loginResponse.hasError {
                if tryIncrementErrorCount(errorType: .login) {
                    reset()
                }
            } else {
                resetErrorCount(errorType: .login)
                persistentIds = []
                ready = true
                let callbacks = readyCallbacks; readyCallbacks.removeAll()
                callbacks.forEach { $0() }
            }
            return
        }

        if msg.type == .DataMessageStanza, let dataMessageStanza = msg.message as? McsProto_DataMessageStanza {
            persistentIds.append(dataMessageStanza.persistentID)

            if config.sendSelectiveAcknowledgements {
                sendSelectiveAck(dataMessageStanza.persistentID)
            }

            handleDataMessage(msg: dataMessageStanza)
        } else if msg.type == .HeartbeatPing, let ping = msg.message as? McsProto_HeartbeatPing {
            handlePing(ping: ping)
        } else if msg.type == .HeartbeatAck {}
        else if msg.type == .IqStanza {
            // Do nothing
        }

        // Reset error count if a read has been successful
        resetErrorCount(errorType: .read)
        resetErrorCount(errorType: .connection)
    }

    private func appDataByKey(msg: McsProto_DataMessageStanza, key: String, doNotRaise: Bool = false) -> String {
        for x in msg.appData {
            if x.key == key {
                return x.value
            }
        }

        if doNotRaise {
            return ""
        }
        return ""
    }

    private func handleDataMessage(msg: McsProto_DataMessageStanza) {
        if appDataByKey(msg: msg, key: "message_type", doNotRaise: true) == "deleted_messages" {
            // The deleted_messages message does not contain data.
            return
        }
        let cryptoKey = String(appDataByKey(msg: msg, key: "crypto-key").dropFirst(3)) // strip dh=
        let salt = String(appDataByKey(msg: msg, key: "encryption").dropFirst(5)) // strip salt=
        let subtype = appDataByKey(msg: msg, key: "subtype")

        guard let credentials else { return }

        guard subtype == credentials.gcm.app_id, !cryptoKey.isEmpty, !salt.isEmpty else { return }

        do {
            let decrypted = try FcmDecryptor.decryptRawData(rawData: msg.rawData, serverPublicKeyString: cryptoKey, saltString: salt, ownPrivateKeyDer: credentials.keys.privateKey, ownSecretString: credentials.keys.secret)

            var removeList = [MessageCallback]()

            for messageCallback in newMessageCallbacks {
                let callback = messageCallback.callback
                let wasSuccessful = callback(FcmPush(data: decrypted, persistentId: msg.persistentID))

                if wasSuccessful {
                    removeList.append(messageCallback)
                }
            }

            newMessageCallbacks.removeAll { removeList.contains($0) }

            if newMessageCallbacks.isEmpty {
                stop()
            }

            resetErrorCount(errorType: .notify)
        } catch {}
    }

    private func handlePing(ping _: McsProto_HeartbeatPing) {
        var req = McsProto_HeartbeatAck()

        if newInputStreamIdAvailable() {
            req.lastStreamIDReceived = getInputStreamId()
        }

        sendMsg(messageWrapper: MessageWrapper(message: req, type: .HeartbeatAck))
    }

    private func getInputStreamId() -> Int32 {
        lastInputStreamIdReported = inputStreamId
        return inputStreamId
    }

    private func newInputStreamIdAvailable() -> Bool {
        lastInputStreamIdReported != inputStreamId
    }

    /// TEARDOWN CONNECTION

    private func stop() {
        connectionGeneration = UUID()
        doListen = false; ready = false
        readyCallbacks.removeAll()
        DispatchQueue.main.async { self.heartbeatTimer?.invalidate(); self.heartbeatTimer = nil }
        connection?.stateUpdateHandler = nil
        connection?.cancel(); connection = nil
        buffer.removeAll(); frameDecoder = GoogleMCSDecoder()
    }
    private func failPending() {
        let callbacks = newMessageCallbacks; newMessageCallbacks.removeAll()
        callbacks.forEach { _ = $0.callback(nil) }
    }
    func reset() {
        stop()
        if !newMessageCallbacks.isEmpty {
            pushQueue.asyncAfter(deadline: .now() + 2) { [weak self] in
                guard let self, !self.newMessageCallbacks.isEmpty, !self.doListen else { return }
                self.start()
            }
        }
    }

    /// ERROR HANDLERS
    private func resetErrorCount(errorType: ErrorType) {
        sequentialErrorCounters[errorType] = 0
    }

    private func tryIncrementErrorCount(errorType: ErrorType) -> Bool {
        if sequentialErrorCounters[errorType] == nil {
            sequentialErrorCounters[errorType] = 0
        }

        sequentialErrorCounters[errorType]! += 1

        if sequentialErrorCounters[errorType]! >= config.abortOnSequentialErrorCount {
            return false
        }
        return true
    }

    private struct MessageCallback: Identifiable, Equatable {
        static func == (lhs: PushReceiver.MessageCallback, rhs: PushReceiver.MessageCallback) -> Bool {
            lhs.id == rhs.id
        }

        let id = UUID()
        let callback: (FcmPush?) -> Bool
    }
}
