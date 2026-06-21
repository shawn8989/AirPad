//
//  NetworkManager.swift
//  AirPad
//
//  Handles Bonjour discovery, TLS connection with NWConnection, send/receive,
//  and high-level commands for trackpad and keyboard events.
//

import Foundation
import Network
import Combine
import UIKit
import CryptoKit
import Security

// Model representing a discovered AirBridge service.
struct DiscoveredService: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let host: String?
    let port: Int?
    let endpoint: NWEndpoint
}

final class NetworkManager: ObservableObject {
    static let shared = NetworkManager()

    // Bonjour
    private let serviceType = "_airbridge._tcp"
    private var browser: NWBrowser?

    // Connection
    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "AirPad.Network")

    // Outgoing packet throttling for mouse moves
    private var pendingMouseDelta: (dx: Double, dy: Double) = (0, 0)
    private var mouseMoveTimer: DispatchSourceTimer?
    private var receiveBuffer = Data()

    @Published var discoveredServices: [DiscoveredService] = []
    @Published var isConnected: Bool = false
    @Published var isPairing: Bool = false
    @Published var connectingServiceID: UUID?
    @Published var lastErrorMessage: String?

    // Server-pushed state updates (e.g., after composite focus commands)
    @Published var pushedOpenWindows: [MacWindowInfo] = []
    @Published var pushedDesktops: [MacDesktopInfo] = []

    // Live Screen
    @Published var liveImage: UIImage?
    @Published var liveFPS: Double = 0
    private var lastFrameTimestamp: CFTimeInterval = 0

    // Debug logging
    @Published var debugLogs: [String] = []
    @Published var debugMouseMoveCount: Int = 0
    @Published var debugScrollCount: Int = 0
    @Published var debugClickCount: Int = 0

    // App Shortcuts and Windows/Desktops request/response tracking
    var installedAppsContinuation: CheckedContinuation<[MacAppInfo], Error>?
    var appIconContinuations: [String: CheckedContinuation<UIImage?, Error>] = [:]
    var windowThumbnailContinuations: [String: CheckedContinuation<UIImage?, Error>] = [:]
    var openWindowsContinuation: CheckedContinuation<[MacWindowInfo], Error>?
    var desktopsContinuation: CheckedContinuation<[MacDesktopInfo], Error>?

    private let maxLogs = 200

    // Auto-reconnect
    private var lastService: DiscoveredService?
    private var reconnectTimer: DispatchSourceTimer?
    private var reconnectBackoff: TimeInterval = 1.0 // seconds, exponential up to max
    private let maxBackoff: TimeInterval = 30.0

    private let security = SecurityManager.shared

    // Security feature flags
    // NOTE: Temporarily disabled so the client speaks plain TCP, matching the
    // current AirBridge server (which listens on plain TCP). This is the known-
    // working configuration for end-to-end connectivity. Re-enable once the
    // server is updated to terminate TLS. Traffic is unencrypted while false.
    var enableTLS: Bool = false
    var enableMessageHMAC: Bool = false // set true when server supports message auth
    private var messageCounter: UInt64 = 0
    private var sessionKey: Data?
    private var sessionSalt: Data?

    // Inbound message auth (feature-flagged)
    var requireInboundHMAC: Bool = false // when true, reject unsigned/invalid inbound messages
    private var inboundLastCounter: UInt64 = 0
    private var inboundLastTimestamp: Int = 0
    private let maxInboundClockSkew: Int = 120 // seconds

    private init() {
        // Start Bonjour browsing on init so the UI can immediately show services
        startBrowsing()
    }

    private func log(_ message: String) {
        let ts = ISO8601DateFormatter().string(from: Date())
        let line = "[\(ts)] \(message)"
        DispatchQueue.main.async {
            self.debugLogs.append(line)
            if self.debugLogs.count > self.maxLogs {
                self.debugLogs.removeFirst(self.debugLogs.count - self.maxLogs)
            }
        }
    }

    private func friendlyError(_ error: NWError) -> String {
        switch error {
        case .posix(let code):
            switch code {
            case .EPERM, .EACCES:
                return "Local Network access denied. Enable it in Settings > Privacy > Local Network."
            case .ENETDOWN, .ENETUNREACH, .ENOTCONN:
                return "Network appears unavailable. Check your Wi‑Fi."
            default:
                return "Network error: \(code.rawValue)"
            }
        case .dns(let code):
            return "Bonjour/DNS error: \(code)"
        case .tls(let status):
            return "TLS error: \(status)"
        @unknown default:
            return "Unexpected network error"
        }
    }

    // Helper: SHA256 fingerprint of leaf certificate
    private func certificateFingerprintSHA256(from trust: SecTrust) -> Data? {
        guard let cert = SecTrustGetCertificateAtIndex(trust, 0) else { return nil }
        let data = SecCertificateCopyData(cert) as Data
        let digest = SHA256.hash(data: data)
        return Data(digest)
    }

    // Helper: constant-time equality for MACs
    private func constantTimeEqual(_ a: Data, _ b: Data) -> Bool {
        if a.count != b.count { return false }
        var diff: UInt8 = 0
        for i in 0..<a.count {
            diff |= a[i] ^ b[i]
        }
        return diff == 0
    }

    // Helper: derive per-session key from shared secret and salt using HKDF-SHA256
    private func deriveSessionKey(sharedSecret: Data, salt: Data) -> Data {
        let ikm = SymmetricKey(data: sharedSecret)
        let info = Data("AirPad-Session-HMAC".utf8)
        let outKey = HKDF<SHA256>.deriveKey(inputKeyMaterial: ikm, salt: salt, info: info, outputByteCount: 32)
        var keyData = Data()
        outKey.withUnsafeBytes { keyData.append(contentsOf: $0) }
        return keyData
    }

    // Helper: Retrieve current HMAC key (session key if available, otherwise shared secret)
    private func currentHMACKey() -> Data? {
        if let sessionKey = self.sessionKey {
            return sessionKey
        }
        if let secret = try? self.security.getSharedSecret() {
            return secret
        }
        return nil
    }

    // Helper: Build secure packet with optional HMAC
    private func buildPacket(type: String, payload: [String: Any]) -> [String: Any] {
        var packet: [String: Any] = ["type": type, "payload": payload]
        if enableMessageHMAC {
            if let secretData = self.currentHMACKey() {
                // Compose nonce, timestamp, and counter
                var nonce = Data(count: 16)
                _ = nonce.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
                let ts = Int(Date().timeIntervalSince1970)
                messageCounter &+= 1
                // Build data to MAC: type + payload JSON + nonce + ts + counter
                let payloadData = (try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])) ?? Data()
                var macInput = Data()
                macInput.append(type.data(using: .utf8) ?? Data())
                macInput.append(payloadData)
                macInput.append(nonce)
                var ts64 = UInt64(ts)
                withUnsafeBytes(of: &ts64) { macInput.append(contentsOf: $0) }
                var ctr = messageCounter
                withUnsafeBytes(of: &ctr) { macInput.append(contentsOf: $0) }
                let mac = SecurityManager.shared.hmacSHA256(data: macInput, key: secretData)
                packet["nonce"] = nonce.base64EncodedString()
                packet["ts"] = ts
                packet["ctr"] = Int(messageCounter)
                packet["hmac"] = mac.base64EncodedString()
            }
        }
        return packet
    }

    // MARK: - Bonjour Browsing
    func startBrowsing() {
        log("Browsing for Bonjour services: \(serviceType)")
        discoveredServices.removeAll()
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true
        let browser = NWBrowser(for: .bonjour(type: serviceType, domain: nil), using: parameters)
        self.browser = browser
        browser.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .failed(let error):
                DispatchQueue.main.async { self.lastErrorMessage = "Browse failed: \(self.friendlyError(error))" }
                self.log("Browser failed: \(error)")
            default: break
            }
        }
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self = self else { return }
            var newServices: [DiscoveredService] = []
            for result in results {
                switch result.endpoint {
                case .service(let name, _, _, _):
                    newServices.append(DiscoveredService(name: name, host: nil, port: nil, endpoint: result.endpoint))
                default:
                    continue
                }
            }
            self.log("Browse results changed: \(results.count) results, \(newServices.count) services")
            DispatchQueue.main.async {
                self.discoveredServices = newServices.sorted { $0.name < $1.name }
            }
        }
        browser.start(queue: queue)
    }

    // MARK: - Connect
    func connect(to service: DiscoveredService) {
        log("Connecting to service: \(service.name)")
        lastService = service
        reconnectBackoff = 1.0
        reconnectTimer?.cancel()
        reconnectTimer = nil

        connectingServiceID = service.id
        lastErrorMessage = nil

        let parameters: NWParameters
        if enableTLS {
            let tls = NWProtocolTLS.Options()
            sec_protocol_options_set_verify_block(tls.securityProtocolOptions, { [weak self] (metadata, trust, complete) in
                guard let self = self else { complete(false); return }
                let trustRef: SecTrust = sec_trust_copy_ref(trust).takeRetainedValue()
                // Evaluate trust using system defaults first
                SecTrustEvaluateAsyncWithError(trustRef, self.queue) { _, ok, _ in
                    var accept = ok
                    if let fp = self.certificateFingerprintSHA256(from: trustRef) {
                        do {
                            if let fpStored = try SecurityManager.shared.getServerCertFingerprint() {
                                if fpStored == fp {
                                    self.log("TLS verify: fingerprint match (system trust=\(ok)).")
                                    // Keep accept as the result of system trust per current policy
                                } else {
                                    self.log("TLS verify: fingerprint mismatch; rejecting. stored=\(fpStored.base64EncodedString()) current=\(fp.base64EncodedString())")
                                    accept = false
                                }
                            } else {
                                if !ok {
                                    self.log("TLS verify: system trust failed and no stored fingerprint; trusting on first use (TOFU) and storing current fingerprint.")
                                } else {
                                    self.log("TLS verify: no stored fingerprint; storing current fingerprint and accepting.")
                                }
                                try? SecurityManager.shared.storeServerCertFingerprint(fp)
                                accept = true
                            }
                        } catch {
                            self.log("TLS verify: error retrieving stored fingerprint: \(error.localizedDescription). Using TOFU and storing current fingerprint.")
                            try? SecurityManager.shared.storeServerCertFingerprint(fp)
                            accept = true
                        }
                    } else {
                        self.log("TLS verify: could not compute certificate fingerprint; deferring to system trust = \(ok).")
                    }
                    complete(accept)
                }
            }, self.queue)
            parameters = NWParameters(tls: tls)
        } else {
            parameters = NWParameters.tcp
        }
        parameters.includePeerToPeer = true
        let connection = NWConnection(to: service.endpoint, using: parameters)
        self.connection = connection

        connection.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .ready:
                self.log("Connection ready")
                DispatchQueue.main.async {
                    self.isConnected = true
                    self.connectingServiceID = nil
                }
                self.inboundLastCounter = 0
                self.inboundLastTimestamp = 0
                self.reconnectBackoff = 1.0
                self.reconnectTimer?.cancel()
                self.reconnectTimer = nil
                self.postConnectHandshake()
                self.receiveLoop()
            case .failed(let error):
                self.log("Connection failed: \(error)")
                DispatchQueue.main.async {
                    self.lastErrorMessage = "Connection failed: \(self.friendlyError(error))"
                    self.isConnected = false
                    self.connectingServiceID = nil
                }
                self.connection?.cancel()
                self.connection = nil
                if self.lastService != nil { self.scheduleReconnect() }
            case .waiting(let error):
                self.log("Connection waiting: \(error)")
                DispatchQueue.main.async { self.lastErrorMessage = "Waiting: \(self.friendlyError(error))" }
            case .cancelled:
                self.log("Connection cancelled")
                DispatchQueue.main.async { self.isConnected = false }
                if self.lastService != nil { self.scheduleReconnect() }
            default:
                break
            }
        }

        connection.start(queue: queue)
    }

    func disconnect() {
        connection?.cancel()
        connection = nil
        lastService = nil // user-initiated disconnect disables auto-reconnect
        reconnectTimer?.cancel()
        reconnectTimer = nil
        DispatchQueue.main.async { self.isConnected = false }
        log("Disconnected by user")
        
        // Clear session keying material
        sessionKey = nil
        sessionSalt = nil
        messageCounter = 0
        
        // Fail any pending App/Window continuations
        if let cont = installedAppsContinuation {
            cont.resume(throwing: NSError(domain: "AirPad.Network", code: -1, userInfo: [NSLocalizedDescriptionKey: "Disconnected"]))
            installedAppsContinuation = nil
        }
        for (key, cont) in appIconContinuations {
            cont.resume(returning: nil)
            appIconContinuations[key] = nil
        }
        appIconContinuations.removeAll()
        for (key, cont) in windowThumbnailContinuations {
            cont.resume(returning: nil)
            windowThumbnailContinuations[key] = nil
        }
        windowThumbnailContinuations.removeAll()
        if let cont = openWindowsContinuation {
            cont.resume(throwing: NSError(domain: "AirPad.Network", code: -1, userInfo: [NSLocalizedDescriptionKey: "Disconnected"]))
            openWindowsContinuation = nil
        }
        if let cont = desktopsContinuation {
            cont.resume(throwing: NSError(domain: "AirPad.Network", code: -1, userInfo: [NSLocalizedDescriptionKey: "Disconnected"]))
            desktopsContinuation = nil
        }
    }

    // MARK: - Trust Management
    func resetTrust() {
        log("Resetting trust: deleting shared secret and fingerprint, disconnecting.")
        // Best-effort deletes; ignore errors but log
        do { _ = try security.deleteSharedSecret() } catch { log("ResetTrust: deleteSharedSecret error: \(error)") }
        do { _ = try security.deleteServerCertFingerprint() } catch { log("ResetTrust: deleteServerCertFingerprint error: \(error)") }

        // Clear in-memory session state
        sessionKey = nil
        sessionSalt = nil
        messageCounter = 0
        inboundLastCounter = 0
        inboundLastTimestamp = 0

        // Disconnect and prevent auto-reconnect
        lastService = nil
        connection?.cancel()
        connection = nil
        reconnectTimer?.cancel()
        reconnectTimer = nil
        DispatchQueue.main.async {
            self.isConnected = false
            self.isPairing = false
            self.connectingServiceID = nil
            self.lastErrorMessage = nil
        }
        log("Trust reset complete")
    }

    private func scheduleReconnect(immediate: Bool = false) {
        guard let service = lastService else { return }
        reconnectTimer?.cancel()
        let delay = immediate ? 0 : reconnectBackoff
        log("Scheduling reconnect in \(String(format: "%.1f", delay))s to \(service.name)")
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + delay)
        timer.setEventHandler { [weak self] in
            guard let self = self, let svc = self.lastService else { return }
            self.log("Attempting reconnect to \(svc.name)")
            self.connect(to: svc)
        }
        timer.resume()
        reconnectTimer = timer
        reconnectBackoff = min(reconnectBackoff * 2, maxBackoff)
    }

    func tryAutoReconnectOnForeground() {
        // Called when app enters foreground; attempt immediate reconnect if we have a previous service and are not connected.
        if !isConnected, lastService != nil {
            scheduleReconnect(immediate: true)
        }
    }

    // MARK: - Pairing and Handshake
    private func postConnectHandshake() {
        queue.async { [weak self] in
            guard let self = self else { return }
            do {
                let deviceID = try self.security.getOrCreateDeviceID()
                // If no shared secret, start pairing
                if (try? self.security.getSharedSecret()) == nil {
                    DispatchQueue.main.async { self.isPairing = true }
                    let pairingRequest = [
                        "deviceID": deviceID,
                        "timestamp": ISO8601DateFormatter().string(from: Date()),
                        "type": "pair_request",
                        "payload": [:] as [String: Any]
                    ]
                    try self.sendRawJSON(pairingRequest)
                } else {
                    // Derive per-session key and send hello with session salt for server-side derivation
                    var salt = Data(count: 16)
                    _ = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
                    self.sessionSalt = salt
                    if let secret = try? self.security.getSharedSecret() {
                        self.sessionKey = self.deriveSessionKey(sharedSecret: secret, salt: salt)
                        self.messageCounter = 0
                    }
                    let saltB64 = salt.base64EncodedString()
                    try self.send(type: "hello", payload: ["deviceID": deviceID, "session_salt": saltB64])
                }
            } catch {
                DispatchQueue.main.async { self.lastErrorMessage = "Handshake error: \(error)" }
            }
        }
    }

    // MARK: - Receive Loop
    private func receiveLoop() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            if let data = data, !data.isEmpty {
                self.receiveBuffer.append(data)
                // Process complete lines (newline-delimited JSON)
                while let nlIndex = self.receiveBuffer.firstIndex(of: 0x0A) { // '\n'
                    let line = self.receiveBuffer.prefix(upTo: nlIndex)
                    // Remove line + newline from buffer
                    self.receiveBuffer.removeSubrange(...nlIndex)
                    self.handleJSONLine(line)
                }
            }
            if isComplete || error != nil {
                self.disconnect()
                return
            }
            self.receiveLoop()
        }
    }

    private func handleJSONLine(_ line: Data) {
        do {
            let obj = try JSONSerialization.jsonObject(with: line) as? [String: Any]
            guard let type = obj?["type"] as? String else { return }
            // Inbound HMAC verification (feature-flagged)
            if requireInboundHMAC || (obj?["hmac"] != nil) {
                let payload = (obj?["payload"] as? [String: Any]) ?? [:]
                let hmacB64 = obj?["hmac"] as? String
                let nonceB64 = obj?["nonce"] as? String
                let ts = obj?["ts"] as? Int
                let ctrInt: Int? = {
                    if let c = obj?["ctr"] as? Int { return c }
                    if let c = obj?["ctr"] as? Double { return Int(c) }
                    return nil
                }()
                if let hmacB64 = hmacB64,
                   let nonceB64 = nonceB64,
                   let ts = ts,
                   let ctrInt = ctrInt,
                   let secretData = self.currentHMACKey(),
                   let hmac = Data(base64Encoded: hmacB64),
                   let nonce = Data(base64Encoded: nonceB64) {

                    let payloadData = (try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])) ?? Data()
                    var macInput = Data()
                    macInput.append(type.data(using: .utf8) ?? Data())
                    macInput.append(payloadData)
                    macInput.append(nonce)
                    var ts64 = UInt64(ts)
                    withUnsafeBytes(of: &ts64) { macInput.append(contentsOf: $0) }
                    var ctr64 = UInt64(ctrInt)
                    withUnsafeBytes(of: &ctr64) { macInput.append(contentsOf: $0) }
                    let expected = self.security.hmacSHA256(data: macInput, key: secretData)

                    if !self.constantTimeEqual(expected, hmac) {
                        self.log("Inbound HMAC: verification failed for type \(type)")
                        if requireInboundHMAC { return }
                    } else {
                        // Replay protection
                        let now = Int(Date().timeIntervalSince1970)
                        let skew = abs(now - ts)
                        if skew > maxInboundClockSkew {
                            self.log("Inbound HMAC: clock skew \(skew)s exceeds \(maxInboundClockSkew)s")
                            if requireInboundHMAC { return }
                        }
                        let ctr = UInt64(ctrInt)
                        if ctr <= inboundLastCounter {
                            self.log("Inbound HMAC: non-monotonic ctr \(ctr) <= \(inboundLastCounter)")
                            if requireInboundHMAC { return }
                        } else {
                            inboundLastCounter = ctr
                            inboundLastTimestamp = ts
                        }
                    }
                } else {
                    self.log("Inbound HMAC: missing fields or secret; \(requireInboundHMAC ? "rejecting" : "accepting for compatibility") for type \(type)")
                    if requireInboundHMAC { return }
                }
            }
            self.log("RX type: \(type)")
            switch type {
            case "pair_response":
                if let secretB64 = obj?["shared_secret"] as? String, let secret = Data(base64Encoded: secretB64) {
                    try? security.storeSharedSecret(secret)
                    DispatchQueue.main.async { self.isPairing = false }
                    // Send hello after pairing, deriving per-session key
                    let deviceID = self.security.currentDeviceID ?? ""
                    var salt = Data(count: 16)
                    _ = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
                    self.sessionSalt = salt
                    if let s = try? self.security.getSharedSecret() {
                        self.sessionKey = self.deriveSessionKey(sharedSecret: s, salt: salt)
                        self.messageCounter = 0
                    }
                    try? self.send(type: "hello", payload: ["deviceID": deviceID, "session_salt": salt.base64EncodedString()])
                }
            
            case "installed_apps":
                if let payload = obj?["payload"] as? [String: Any],
                   let items = payload["apps"] as? [[String: Any]] {
                    let apps: [MacAppInfo] = items.compactMap { dict in
                        guard let id = dict["id"] as? String,
                              let name = dict["name"] as? String else { return nil }
                        let bundleID = (dict["bundleIdentifier"] as? String) ?? id
                        let isRunning = (dict["isRunning"] as? Bool) ?? false
                        var lastLaunchedDate: Date? = nil
                        if let last = dict["lastLaunched"] as? String {
                            lastLaunchedDate = ISO8601DateFormatter().date(from: last)
                        } else if let ts = dict["lastLaunched"] as? Double {
                            lastLaunchedDate = Date(timeIntervalSince1970: ts)
                        }
                        return MacAppInfo(id: id, name: name, bundleIdentifier: bundleID, icon: nil, isRunning: isRunning, lastLaunched: lastLaunchedDate)
                    }
                    if let cont = installedAppsContinuation {
                        cont.resume(returning: apps)
                        installedAppsContinuation = nil
                    }
                }

            case "app_icon":
                if let payload = obj?["payload"] as? [String: Any],
                   let bundleID = payload["bundleIdentifier"] as? String {
                    var image: UIImage? = nil
                    if let b64 = payload["data"] as? String,
                       let data = Data(base64Encoded: b64) {
                        image = UIImage(data: data)
                    }
                    if let cont = appIconContinuations[bundleID] {
                        cont.resume(returning: image)
                        appIconContinuations.removeValue(forKey: bundleID)
                    }
                }

            case "window_thumbnail":
                if let payload = obj?["payload"] as? [String: Any],
                   let windowID = payload["windowID"] as? String {
                    var image: UIImage? = nil
                    if let b64 = payload["data"] as? String, let data = Data(base64Encoded: b64) {
                        image = UIImage(data: data)
                    }
                    if let cont = windowThumbnailContinuations[windowID] {
                        cont.resume(returning: image)
                        windowThumbnailContinuations.removeValue(forKey: windowID)
                    }
                }

            case "open_windows":
                if let payload = obj?["payload"] as? [String: Any],
                   let items = payload["windows"] as? [[String: Any]] {
                    let windows: [MacWindowInfo] = items.compactMap { dict in
                        guard let id = dict["windowID"] as? String,
                              let title = dict["title"] as? String,
                              let bundleID = dict["appBundleIdentifier"] as? String,
                              let appName = dict["appName"] as? String else { return nil }
                        let isMinimized = (dict["isMinimized"] as? Bool) ?? false
                        let isOnScreen = (dict["isOnScreen"] as? Bool) ?? true
                        let space = dict["space"] as? Int
                        let ownerPID = dict["ownerPID"] as? Int
                        return MacWindowInfo(id: id, title: title, appBundleIdentifier: bundleID, appName: appName, isMinimized: isMinimized, isOnScreen: isOnScreen, space: space, ownerPID: ownerPID, appIcon: nil)
                    }
                    if let cont = openWindowsContinuation {
                        cont.resume(returning: windows)
                        openWindowsContinuation = nil
                    }
                    // Also publish as a push update for observers
                    DispatchQueue.main.async {
                        self.pushedOpenWindows = windows
                    }
                }

            case "desktops":
                if let payload = obj?["payload"] as? [String: Any],
                   let items = payload["desktops"] as? [[String: Any]] {
                    var desktops: [MacDesktopInfo] = items.compactMap { d in
                        guard let id = d["id"] as? String,
                              let index = d["index"] as? Int,
                              let isActive = d["isActive"] as? Bool else { return nil }
                        let name = d["name"] as? String
                        return MacDesktopInfo(id: id, index: index, name: name, isActive: isActive)
                    }
                    if let currentIndex = payload["current_desktop_index"] as? Int {
                        desktops = desktops.map { d in
                            var m = d
                            m.isActive = (m.index == currentIndex)
                            return m
                        }
                    }
                    if let cont = desktopsContinuation {
                        cont.resume(returning: desktops)
                        desktopsContinuation = nil
                    }
                    // Also publish as a push update for observers
                    DispatchQueue.main.async {
                        self.pushedDesktops = desktops
                    }
                }

            case "error":
                let message = obj?["message"] as? String ?? "Unknown error"
                DispatchQueue.main.async { self.lastErrorMessage = message }
            case "video_jpeg":
                if let payload = obj?["payload"] as? [String: Any],
                   let b64 = payload["data"] as? String,
                   let data = Data(base64Encoded: b64) {
                    // Decode JPEG to UIImage off-main, then publish on main
                    if let image = UIImage(data: data) {
                        let now = CACurrentMediaTime()
                        let dt = now - self.lastFrameTimestamp
                        self.lastFrameTimestamp = now
                        let fps = dt > 0 ? 1.0 / dt : 0
                        DispatchQueue.main.async {
                            self.liveImage = image
                            // Low-pass filter FPS to stabilize display
                            self.liveFPS = self.liveFPS * 0.8 + fps * 0.2
                        }
                    }
                }
            case "server_capabilities":
                if let payload = obj?["payload"] as? [String: Any] {
                    if let requireInbound = payload["requireInboundHMAC"] as? Bool {
                        self.requireInboundHMAC = requireInbound
                        self.log("Capabilities: requireInboundHMAC=\(requireInbound)")
                    }
                    if let requireClientHMAC = payload["requireClientHMAC"] as? Bool {
                        self.enableMessageHMAC = requireClientHMAC
                        self.log("Capabilities: enableMessageHMAC=\(requireClientHMAC)")
                    }
                }
            default:
                break
            }
        } catch {
            DispatchQueue.main.async { self.lastErrorMessage = "Parse error: \(error)" }
        }
    }

    // MARK: - Sending
    private func sendRawJSON(_ object: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [])
        var line = data
        line.append(0x0A) // Newline for NDJSON framing
        connection?.send(content: line, completion: .contentProcessed { _ in })
        if let t = object["type"] as? String { self.log("TX type: \(t)") }
    }

    func send(type: String, payload: [String: Any]) throws {
        let packet = buildPacket(type: type, payload: payload)
        try sendRawJSON(packet)
    }

    // Public high-level events
    func sendMouseDelta(dx: Double, dy: Double) {
        // Accumulate and throttle at ~120 Hz
        pendingMouseDelta.dx += dx
        pendingMouseDelta.dy += dy
        if mouseMoveTimer == nil {
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now(), repeating: .milliseconds(8), leeway: .milliseconds(2))
            timer.setEventHandler { [weak self] in
                guard let self = self else { return }
                let delta = self.pendingMouseDelta
                // Quantize to integer pixel steps and preserve fractional remainder.
                let stepX = Int(delta.dx.rounded())
                let stepY = Int(delta.dy.rounded())
                if stepX != 0 || stepY != 0 {
                    // Subtract the sent integer steps to keep fractional remainder for the next tick.
                    self.pendingMouseDelta.dx -= Double(stepX)
                    self.pendingMouseDelta.dy -= Double(stepY)
                    try? self.send(type: "mouse_move", payload: ["dx": stepX, "dy": stepY])
                    DispatchQueue.main.async { self.debugMouseMoveCount += 1 }
                }
            }
            timer.resume()
            mouseMoveTimer = timer
        }
    }

    func sendScroll(dx: Double, dy: Double) {
        try? send(type: "scroll", payload: ["dx": dx, "dy": dy])
        DispatchQueue.main.async { self.debugScrollCount += 1 }
    }

    func sendClick(button: String = "left") {
        try? send(type: "mouse_click", payload: ["button": button])
        DispatchQueue.main.async { self.debugClickCount += 1 }
    }

    func sendMouseDown(button: String = "left") {
        try? send(type: "mouse_down", payload: ["button": button])
    }

    func sendMouseUp(button: String = "left") {
        try? send(type: "mouse_up", payload: ["button": button])
    }

    func sendAction(_ name: String) {
        try? send(type: "action", payload: ["name": name])
    }

    func sendSwipe(fingers: Int, direction: String) {
        try? send(type: "swipe", payload: ["fingers": fingers, "direction": direction])
    }

    func sendKeyDown(keyCode: UInt16) {
        try? send(type: "key_down", payload: ["keyCode": Int(keyCode)])
    }

    func sendKeyUp(keyCode: UInt16) {
        try? send(type: "key_up", payload: ["keyCode": Int(keyCode)])
    }

    // MARK: - Live Screen control
    func startLiveScreen(maxWidth: Int = 1024, quality: Double = 0.7) {
        let q = max(0.1, min(1.0, quality))
        try? send(type: "video_start", payload: ["format": "jpeg", "maxWidth": maxWidth, "quality": q])
    }

    func stopLiveScreen() {
        try? send(type: "video_stop", payload: [:])
    }

    #if DEBUG
    // Test-only helper to validate HKDF derivation determinism in unit tests.
    internal func test_deriveSessionKey(sharedSecret: Data, salt: Data) -> Data {
        return deriveSessionKey(sharedSecret: sharedSecret, salt: salt)
    }
    #endif
}

