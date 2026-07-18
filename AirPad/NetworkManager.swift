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

    // Outgoing input coalescing with backpressure (mouse + scroll). All access on `queue`.
    private var pendingMouseDelta: (dx: Double, dy: Double) = (0, 0)
    private var pendingScrollDelta: (dx: Double, dy: Double) = (0, 0)
    // Small in-flight window (2) instead of strict stop-and-wait: with one
    // packet in flight the send rate is gated on TLS-stack completions, which
    // gets choppy under Wi-Fi jitter. Two keeps the pipe busy while still
    // bounding queue buildup (the original slowdown bug).
    private var inputInFlight = 0
    // Owned by `queue`; flushed to the @Published debug counters in batches.
    private var localMoveCount = 0
    private var localScrollCount = 0
    private var receiveBuffer = Data()

    @Published var discoveredServices: [DiscoveredService] = []
    @Published var isConnected: Bool = false
    @Published var isPairing: Bool = false
    @Published var connectingServiceID: UUID?
    @Published var lastErrorMessage: String?

    // Which Mac we're currently talking to (learned from the server's server_info
    // message). Per-Mac keys are stored under this ID so one AirPad can pair with
    // and switch between multiple Macs.
    var currentMacID: String?
    @Published var currentMacName: String?
    @Published var lastFetchedClipboard: String?

    struct NowPlayingInfo: Equatable {
        var playing: Bool
        var title: String
        var artist: String
        var app: String
        var volume: Int?
        var muted: Bool
    }
    @Published var nowPlaying: NowPlayingInfo?

    // True while the Mac reports keyboard focus is in a text field (drives
    // the auto keyboard popup). Set by the "text_focus" message.
    @Published var macTextFieldFocused = false
    // Composite miniatures of each Mac desktop, keyed by desktop (Space) id.
    @Published var desktopPreviews: [String: UIImage] = [:]
    // Non-nil when the Mac reported a streaming problem (e.g. missing
    // Screen Recording permission).
    @Published var streamErrorReason: String?

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
    // Stage 1: client uses TLS-PSK (see AirSecureChannel.makePSKParameters) to
    // match the AirBridge server's PSK listener — encrypted and mutually
    // authenticated via a shared key. Set false only for plain-TCP debugging.
    var enableTLS: Bool = true
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

    // Shared formatter: allocating an ISO8601DateFormatter per log line is
    // expensive enough to matter on hot paths.
    private static let logTimestampFormatter = ISO8601DateFormatter()

    private func log(_ message: String) {
        let ts = Self.logTimestampFormatter.string(from: Date())
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
        // A backgrounded browser comes back wedged: it stays "running" but
        // never reports results again. Always start from a fresh one.
        browser?.cancel()
        discoveredServices.removeAll()
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true
        let browser = NWBrowser(for: .bonjour(type: serviceType, domain: nil), using: parameters)
        self.browser = browser
        browser.stateUpdateHandler = { [weak self, weak browser] state in
            guard let self = self else { return }
            switch state {
            case .failed(let error):
                DispatchQueue.main.async { self.lastErrorMessage = "Browse failed: \(self.friendlyError(error))" }
                self.log("Browser failed: \(error) — restarting in 1.5s")
                self.queue.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                    // Only restart if this failed browser is still the current one.
                    guard let self, self.browser === browser else { return }
                    DispatchQueue.main.async { self.startBrowsing() }
                }
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

    /// AirBridge's fixed listening port (it falls back to ephemeral only if taken).
    static let defaultPort: UInt16 = 52417

    /// Connect straight to a host (IP or DNS name) — for VPN/Tailscale setups
    /// where Bonjour discovery can't cross networks. Pairing and encryption
    /// work exactly as on the local network.
    func connectToAddress(_ host: String, port: UInt16 = NetworkManager.defaultPort) {
        let trimmed = host.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let nwPort = NWEndpoint.Port(rawValue: port) else { return }
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(trimmed), port: nwPort)
        connect(to: DiscoveredService(name: trimmed, host: trimmed, port: Int(port), endpoint: endpoint))
    }

    // MARK: - Connect
    func connect(to service: DiscoveredService) {
        log("Connecting to service: \(service.name)")
        // Tear down any existing connection so the user can switch Macs on the fly.
        connection?.cancel()
        connection = nil
        currentMacID = nil
        DispatchQueue.main.async { self.currentMacName = nil }

        lastService = service
        reconnectBackoff = 1.0
        reconnectTimer?.cancel()
        reconnectTimer = nil
        // Desktop ids can change across Mac restarts; drop previews keyed by
        // the old session's ids so stale images never stick to wrong cards.
        DispatchQueue.main.async { self.desktopPreviews = [:] }

        connectingServiceID = service.id
        lastErrorMessage = nil

        let parameters: NWParameters
        if enableTLS {
            // TLS-PSK (Stage 1): mutually-authenticated, encrypted channel via a
            // shared key. No certificate / TOFU verify-block needed — the PSK
            // itself authenticates both peers. The legacy cert-pinning helpers
            // (certificateFingerprintSHA256 / server-cert-fingerprint storage)
            // are retained but unused until/unless we add certificate TLS.
            // Shared-key TLS-PSK transport (known-working). Per-device identity
            // and authentication are handled at the application layer after
            // connect (Stage 2b), not via the TLS PSK identity.
            parameters = AirSecureChannel.makePSKParameters(psk: AirSecureChannel.stage1PSK,
                                                            identity: AirSecureChannel.stage1Identity)
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
                // Reset input-coalescing state for the fresh connection.
                self.inputInFlight = 0
                self.pendingMouseDelta = (0, 0)
                self.pendingScrollDelta = (0, 0)
                self.reconnectBackoff = 1.0
                self.reconnectTimer?.cancel()
                self.reconnectTimer = nil
                self.postConnectHandshake()
                self.startHeartbeat()
                self.receiveLoop()
            case .failed(let error):
                self.log("Connection failed: \(error)")
                DispatchQueue.main.async {
                    self.lastErrorMessage = "Connection failed: \(self.friendlyError(error))"
                    self.isConnected = false
                    self.connectingServiceID = nil
                }
                self.stopHeartbeat()
                self.connection?.cancel()
                self.connection = nil
                if self.lastService != nil { self.scheduleReconnect() }
            case .waiting(let error):
                self.log("Connection waiting: \(error)")
                DispatchQueue.main.async { self.lastErrorMessage = "Waiting: \(self.friendlyError(error))" }
            case .cancelled:
                self.log("Connection cancelled")
                self.stopHeartbeat()
                DispatchQueue.main.async { self.isConnected = false }
                if self.lastService != nil { self.scheduleReconnect() }
            default:
                break
            }
        }

        connection.start(queue: queue)
    }

    // MARK: - QR pairing (client)

    /// Set after scanning a pairing QR; consumed by the next hello handshake.
    private var pendingQRPairing: (macID: String, macName: String, secret: Data)?

    /// Parses a scanned QR payload; on success stores the pending secret and
    /// connects to the matching Mac. Returns a user-facing error, or nil.
    func handleScannedQR(_ string: String) -> String? {
        guard let data = string.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (obj["v"] as? Int) == 1,
              let macID = obj["macID"] as? String,
              let macName = obj["macName"] as? String,
              let secretB64 = obj["qrSecret"] as? String,
              let secret = Data(base64Encoded: secretB64) else {
            return "That doesn't look like an AirBridge pairing code."
        }
        guard let service = discoveredServices.first(where: { $0.name == macName }) else {
            return "Found the code for “\(macName)”, but that Mac isn't visible on this network. Make sure AirBridge is running and both devices share the same Wi-Fi."
        }
        queue.async { [weak self] in
            self?.pendingQRPairing = (macID, macName, secret)
        }
        connect(to: service)
        return nil
    }

    /// Same derivation as AirBridge: HKDF-SHA256(qrSecret, salt: deviceID,
    /// info: "AirPad-QR-Pair", 32 bytes).
    private func deriveQRPairSecret(qrSecret: Data, deviceID: String) -> Data {
        let key = HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: qrSecret),
                                         salt: Data(deviceID.utf8),
                                         info: Data("AirPad-QR-Pair".utf8),
                                         outputByteCount: 32)
        var out = Data()
        key.withUnsafeBytes { out.append(contentsOf: $0) }
        return out
    }

    // MARK: - Heartbeat
    // Detects half-dead connections (Mac asleep, Wi-Fi drop) that TCP won't
    // surface for minutes: ping every 15s; if no pong within ~35s, cancel the
    // connection so auto-reconnect takes over instead of hanging.
    private var heartbeatTimer: DispatchSourceTimer?
    private var lastPongAt: TimeInterval = 0

    private func startHeartbeat() {
        stopHeartbeat()
        lastPongAt = CACurrentMediaTime()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 15, repeating: 15)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            if CACurrentMediaTime() - self.lastPongAt > 35 {
                self.log("Heartbeat timeout — dropping connection to trigger reconnect")
                DispatchQueue.main.async { self.lastErrorMessage = "Connection to the Mac was lost." }
                self.connection?.cancel()
                return
            }
            try? self.send(type: "ping", payload: [:])
        }
        timer.resume()
        heartbeatTimer = timer
    }

    private func stopHeartbeat() {
        heartbeatTimer?.cancel()
        heartbeatTimer = nil
    }

    func disconnect() {
        stopHeartbeat()
        // Tell the Mac we're leaving so it releases input state and updates
        // its dashboard IMMEDIATELY, instead of waiting for the socket to die.
        try? send(type: "bye", payload: [:])
        let dying = connection
        connection = nil
        // Give the bye a moment on the wire before killing the socket.
        queue.asyncAfter(deadline: .now() + 0.25) { dying?.cancel() }
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
                // Identify ourselves. The server replies with server_info (its
                // macID), then either an auth_challenge (already paired with this
                // Mac) or, after user approval, a pair_response.
                var payload: [String: Any] = ["deviceID": deviceID,
                                              "deviceName": UIDevice.current.name]
                // QR pairing: prove we scanned the code shown on the Mac's
                // screen — the server pairs us instantly, no approval dialog.
                if let qr = self.pendingQRPairing {
                    let proof = self.security.hmacSHA256(data: Data(deviceID.utf8), key: qr.secret)
                    payload["qrProof"] = proof.base64EncodedString()
                }
                try self.send(type: "hello", payload: payload)
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
            // Live-screen frames arrive up to ~30x/s; logging each one hops to
            // the main thread and invalidates SwiftUI, adding input latency.
            if type != "video_jpeg" { self.log("RX type: \(type)") }
            switch type {
            case "server_info":
                // The Mac told us its stable ID + name. Remember it so we use the
                // right per-Mac key (and can show which Mac we're controlling).
                if let payload = obj?["payload"] as? [String: Any], let macID = payload["macID"] as? String {
                    self.currentMacID = macID
                    let macName = payload["macName"] as? String
                    let macAddress = payload["macAddress"] as? String
                    DispatchQueue.main.async {
                        self.currentMacName = macName
                        // Remember this Mac (name + hardware address) so the
                        // connect screen can offer Wake-on-LAN later.
                        KnownMacStore.upsert(id: macID, name: macName ?? "Mac", macAddress: macAddress)
                    }
                }

            case "pong":
                self.lastPongAt = CACurrentMediaTime()

            case "text_focus":
                if let payload = obj?["payload"] as? [String: Any], let focused = payload["focused"] as? Bool {
                    DispatchQueue.main.async { self.macTextFieldFocused = focused }
                }

            case "stream_error":
                if let payload = obj?["payload"] as? [String: Any], let reason = payload["reason"] as? String {
                    DispatchQueue.main.async { self.streamErrorReason = reason }
                }

            case "now_playing":
                if let payload = obj?["payload"] as? [String: Any] {
                    let info = NowPlayingInfo(
                        playing: payload["playing"] as? Bool ?? false,
                        title: payload["title"] as? String ?? "",
                        artist: payload["artist"] as? String ?? "",
                        app: payload["app"] as? String ?? "",
                        volume: payload["volume"] as? Int,
                        muted: payload["muted"] as? Bool ?? false)
                    DispatchQueue.main.async { self.nowPlaying = info }
                }

            case "pair_qr_ok":
                // The Mac accepted our QR proof: store the derived per-Mac
                // secret (matches what the server stored) and we're done —
                // the connection is already authenticated server-side.
                if let qr = self.pendingQRPairing,
                   let deviceID = try? self.security.getOrCreateDeviceID() {
                    let derived = self.deriveQRPairSecret(qrSecret: qr.secret, deviceID: deviceID)
                    try? self.security.storeSharedSecret(derived, forMac: qr.macID)
                    self.pendingQRPairing = nil
                    self.log("QR pairing complete with \(qr.macName)")
                    DispatchQueue.main.async { self.isPairing = false }
                }

            case "clipboard_data":
                // Reply to requestMacClipboard: put the Mac's clipboard on ours.
                if let payload = obj?["payload"] as? [String: Any], let text = payload["text"] as? String {
                    DispatchQueue.main.async {
                        UIPasteboard.general.string = text
                        self.lastFetchedClipboard = text
                    }
                }

            case "pair_response":
                // Store the freshly paired secret under THIS Mac's ID. The server
                // authorized us on approval, so there's no further handshake.
                if let secretB64 = obj?["shared_secret"] as? String,
                   let secret = Data(base64Encoded: secretB64),
                   let macID = self.currentMacID {
                    try? security.storeSharedSecret(secret, forMac: macID)
                    DispatchQueue.main.async { self.isPairing = false }
                }

            case "auth_challenge":
                // The server sent a random nonce; prove we hold THIS Mac's secret
                // by returning HMAC(secret, nonce). Until this passes, the server
                // will not execute any of our commands.
                if let payload = obj?["payload"] as? [String: Any],
                   let nonceB64 = payload["nonce"] as? String,
                   let nonce = Data(base64Encoded: nonceB64),
                   let macID = self.currentMacID,
                   let secret = (try? self.security.getSharedSecret(forMac: macID)) ?? nil {
                    let proof = self.security.hmacSHA256(data: nonce, key: secret)
                    try? self.send(type: "auth_proof", payload: ["proof": proof.base64EncodedString()])
                } else {
                    // Server thinks we're known but we have no key for this Mac
                    // (e.g. an install that predates per-Mac keys). Re-pair.
                    self.log("auth_challenge: no per-Mac secret; requesting re-pair")
                    DispatchQueue.main.async { self.isPairing = true }
                    try? self.send(type: "pair_request", payload: [:])
                }

            case "auth_reset":
                // Server could not verify our secret (typically a stale pairing).
                // Clear THIS Mac's key so the automatic reconnect re-pairs.
                self.log("Server requested re-pair; clearing per-Mac secret")
                if let macID = self.currentMacID { try? self.security.deleteSharedSecret(forMac: macID) }
                DispatchQueue.main.async { self.isPairing = true }

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

            case "desktop_preview":
                // Streamed composite miniature of one desktop (Space).
                if let payload = obj?["payload"] as? [String: Any],
                   let desktopID = payload["id"] as? String,
                   let b64 = payload["data"] as? String,
                   let data = Data(base64Encoded: b64),
                   let image = UIImage(data: data) {
                    DispatchQueue.main.async { self.desktopPreviews[desktopID] = image }
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
        queue.async { [weak self] in
            guard let self = self else { return }
            self.pendingMouseDelta.dx += dx
            self.pendingMouseDelta.dy += dy
            self.pumpInput()
        }
    }

    func sendScroll(dx: Double, dy: Double) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.pendingScrollDelta.dx += dx
            self.pendingScrollDelta.dy += dy
            self.pumpInput()
            // Batched like the mouse counter to avoid per-event main-thread hops.
            self.localScrollCount += 1
            if self.localScrollCount % 20 == 0 {
                let c = self.localScrollCount
                DispatchQueue.main.async { self.debugScrollCount = c }
            }
        }
    }

    // Coalesce high-rate mouse/scroll input with backpressure: only one such
    // packet is in flight at a time; deltas accumulated meanwhile are merged and
    // sent on completion (latest-wins). This stops the send queue from backing up
    // over time — the slowdown that previously needed a reconnect to clear.
    // Must be called on `queue`.
    private func pumpInput() {
        guard inputInFlight < 2 else { return }
        // Mouse first: quantize to integer pixels, keep the fractional remainder.
        let stepX = Int(pendingMouseDelta.dx.rounded())
        let stepY = Int(pendingMouseDelta.dy.rounded())
        if stepX != 0 || stepY != 0 {
            pendingMouseDelta.dx -= Double(stepX)
            pendingMouseDelta.dy -= Double(stepY)
            sendCoalesced(type: "mouse_move", payload: ["dx": stepX, "dy": stepY])
            // Batch the debug counter: a main-thread hop + SwiftUI invalidation
            // per packet at ~120 Hz adds measurable input latency.
            localMoveCount += 1
            if localMoveCount % 20 == 0 {
                let c = localMoveCount
                DispatchQueue.main.async { self.debugMouseMoveCount = c }
            }
            return
        }
        // Then scroll.
        if pendingScrollDelta.dx != 0 || pendingScrollDelta.dy != 0 {
            let dx = pendingScrollDelta.dx, dy = pendingScrollDelta.dy
            pendingScrollDelta = (0, 0)
            sendCoalesced(type: "scroll", payload: ["dx": dx, "dy": dy])
            return
        }
    }

    // Send one coalesced packet and re-pump when it completes. Must be on `queue`.
    private func sendCoalesced(type: String, payload: [String: Any]) {
        guard let conn = connection else { inputInFlight = 0; return }
        do {
            let packet = buildPacket(type: type, payload: payload)
            var line = try JSONSerialization.data(withJSONObject: packet, options: [])
            line.append(0x0A)
            inputInFlight += 1
            conn.send(content: line, completion: .contentProcessed { [weak self] _ in
                guard let self = self else { return }
                // NWConnection completions run on the connection's queue (== self.queue).
                self.inputInFlight = max(0, self.inputInFlight - 1)
                self.pumpInput()
            })
        } catch {
            inputInFlight = max(0, inputInFlight - 1)
        }
    }

    func sendClick(button: String = "left", count: Int = 1) {
        try? send(type: "mouse_click", payload: ["button": button, "count": count])
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

    func sendSwipe(fingers: Int, direction: String, skipFullscreen: Bool = false) {
        // skipFullscreen: the Desktop buttons hop over full-screen-app Spaces
        // (they want real desktops); gesture swipes keep native traversal.
        try? send(type: "swipe", payload: ["fingers": fingers, "direction": direction,
                                           "skipFullscreen": skipFullscreen])
    }

    // Two-finger horizontal flick -> browser back/forward. direction: "back"|"forward".
    func sendNav(direction: String) {
        try? send(type: "nav", payload: ["direction": direction])
    }

    // Pinch -> zoom. zoomIn = true for pinch-out (zoom in), false for pinch-in.
    func sendPinch(zoomIn: Bool) {
        try? send(type: "pinch", payload: ["direction": zoomIn ? "in" : "out"])
    }

    // Absolute cursor position, normalized 0...1 on the Mac's main display
    // (Live Screen "tap what you see").
    func sendMouseMoveAbs(x: Double, y: Double) {
        try? send(type: "mouse_move_abs", payload: ["x": x, "y": y])
    }

    // A key with explicit modifiers (accessory-bar shortcuts like ⌘C); the
    // Mac applies the flags to the key events directly.
    func sendKeyCombo(_ keyCode: UInt16, command: Bool = false, option: Bool = false,
                      control: Bool = false, shift: Bool = false) {
        try? send(type: "key_combo", payload: [
            "keyCode": Int(keyCode),
            "command": command, "option": option, "control": control, "shift": shift
        ])
    }

    // Ask the Mac for the current track + system volume; reply arrives as
    // "now_playing" and lands in the nowPlaying published property.
    func requestNowPlaying() {
        try? send(type: "now_playing_get", payload: [:])
    }

    // Set the Mac's output volume (0-100).
    func sendSetVolume(_ level: Int) {
        try? send(type: "set_volume", payload: ["level": max(0, min(100, level))])
    }

    // Media/system control: volume_up/down, mute, play_pause, next, previous,
    // brightness_up/down, lock_screen.
    func sendMedia(action: String) {
        try? send(type: "media", payload: ["action": action])
    }

    // Types a whole string on the Mac (dictation / paste-through).
    func sendTypeText(_ text: String) {
        guard !text.isEmpty else { return }
        try? send(type: "type_text", payload: ["text": text])
    }

    // Clipboard sync: push the given text into the Mac's clipboard.
    func sendClipboardSet(_ text: String) {
        try? send(type: "clipboard_set", payload: ["text": text])
    }

    // Clipboard sync: ask the Mac for its clipboard; reply arrives as
    // "clipboard_data" and is placed on the iOS pasteboard.
    func requestMacClipboard() {
        try? send(type: "clipboard_get", payload: [:])
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

