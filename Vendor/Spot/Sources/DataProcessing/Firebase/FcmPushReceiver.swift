//
//  FcmPushReceiver.swift
//
//
//  Created by Leon Böttger on 06.12.24.
//

import CryptoKit
import Foundation
import LUI
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
    private var credentials: FcmCredentials?
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

        do {
            credentials = try KeychainStore.shared.load(FcmCredentials.self, for: .fcmCredentials)
        } catch {
            showAlert(title: "Secure Storage Error", message: error.localizedDescription)
        }
        config = FcmPushClientConfig()
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

            if !doListen {
                checkinOrRegister()
            }

            isListening()

            pushQueue.asyncAfter(deadline: .now() + 20) { [self] in
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

    func registerForLogin(callback: @escaping () -> Void) {
        pushQueue.async {
            self.checkinOrRegister(callback: callback)
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

    private func checkinOrRegister(callback: (() -> Void)? = nil) {
        // Check in if you have credentials otherwise register as a new client.
        do {
            if credentials == nil {
                credentials = try KeychainStore.shared.load(FcmCredentials.self, for: .fcmCredentials)
            }
            registerer = FcmRegister(config: fcmConfig, credentials: credentials)
            let result = try registerer?.checkinOrRegister()
            registerer?.close()
            try storeCredentials(credentials: result)
        } catch {
            DispatchQueue.main.async {
                callback?()
                showAlert(title: "Google-Verbindung", message: "Die Google-Registrierung ist fehlgeschlagen. Bitte erneut versuchen.")
            }
            return
        }

        DispatchQueue.main.async {
            callback?()
        }

        if !newMessageCallbacks.isEmpty {
            start()
        }
    }

    private func listen() {
        connectWithRetry()
        login()
        startReading()
    }

    private func connectWithRetry() {
        var connected = false

        while !connected, doListen {
            connected = connect()

            if !connected {
                let sleepTime = config.startSecondsBeforeRetryConnect

                Thread.sleep(forTimeInterval: sleepTime)
            }
        }
    }

    private func connect() -> Bool {
        let semaphore = DispatchSemaphore(value: 0)
        var success = false

        connection = openConnection { result in
            success = result
            semaphore.signal() // Release the semaphore when the callback is executed
        }

        // Wait for the semaphore signal (blocks the thread until signal is called)
        semaphore.wait()

        return success
    }

    private func openConnection(callback: @escaping (Bool) -> Void) -> NWConnection {
        let parameters = NWParameters.tls // Use standard TLS parameters

        let MCS_HOST = "mtalk.google.com"
        let MCS_PORT: UInt16 = 5228

        let connection = NWConnection(host: NWEndpoint.Host(MCS_HOST), port: NWEndpoint.Port(rawValue: MCS_PORT)!, using: parameters)
        connection.start(queue: networkQueue)

        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                callback(true)
                connection.stateUpdateHandler = nil
            case .cancelled:
                callback(false)
                connection.stateUpdateHandler = nil
            case let .failed(error):
                callback(false)
                connection.stateUpdateHandler = nil
            default:
                break
            }
        }

        return connection
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

        var connectionInvalid = false

        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
            self.pushQueue.async {
                if connectionInvalid || !self.doListen {
                    return
                }

                if let data {
                    self.buffer.append(data)

                    do {
                        try self.checkForMessages()
                    } catch {
                        self.buffer = Data()
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

    private func checkForMessages() throws {
        var tag: UInt8 = 0
        bufferIndex = 0

        if firstMessage {
            guard let firstData = readBuffer(length: 2) else { return }

            let version = firstData[firstData.startIndex]
            tag = firstData[firstData.startIndex + 1]

            if version < MCS_VERSION, version != 38 {
                throw NSError(domain: "Unsupported version", code: 0)
            }

            firstMessage = false
        } else {
            guard let tagData = readBuffer(length: 1) else { return }
            tag = tagData[tagData.startIndex]
        }

        let size = try readVarint32()

        if size < 0 {
            throw NSError(domain: "Invalid message size", code: 0)
        }

        guard let buf = readBuffer(length: size) else { return }

        guard let msgClass = MCSMessageTag.fromInt(Int(tag)) else {
            throw NSError(domain: "Unsupported message tag", code: 0)
        }

        guard let payloadProto = msgClass.getInstance(with: buf) else {
            throw NSError(domain: "Could not deserialize payload", code: 0)
        }
        buffer.removeFirst(bufferIndex)

        if !buffer.isEmpty {
            try checkForMessages()
        }

        handleMessage(msg: MessageWrapper(message: payloadProto, type: msgClass))
    }

    private func readVarint32() throws -> Int {
        var result = 0
        var shift = 0

        while true {
            guard let byteData = readBuffer(length: 1)?.first else {
                throw NSError(domain: "Error reading varint32", code: 0)
            }

            result |= (Int(byteData) & 0x7F) << shift
            if (byteData & 0x80) == 0 {
                break
            }
            shift += 7

            if shift >= 32 {
                throw NSError(domain: "Too large integer", code: 0)
            }
        }

        return result
    }

    private func readBuffer(length: Int) -> Data? {
        // read from buffer index to length
        if length + bufferIndex > buffer.count {
            return nil
        }

        let startIndex = buffer.startIndex + bufferIndex
        let data = buffer[startIndex ..< startIndex + length]
        bufferIndex += length

        return data
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
        fatalError("couldn't find in app_data \(key)")
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

        if subtype != credentials.gcm.app_id {}

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
        if connection == nil {
            return
        }

        registerer = nil
        heartbeatTimer?.invalidate()
        buffer = Data()
        bufferIndex = 0
        doListen = false

        connection?.cancel()

        while connection?.state != .cancelled {
            Thread.sleep(forTimeInterval: 1)
        }

        connection = nil
    }

    func reset() {
        stop()
        Thread.sleep(forTimeInterval: 30)

        checkinOrRegister()
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
        let callback: (FcmPush) -> Bool
    }
}
