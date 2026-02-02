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

    @Published var discoveredServices: [DiscoveredService] = []
    @Published var isConnected: Bool = false
    @Published var isPairing: Bool = false
    @Published var connectingServiceID: UUID?
    @Published var lastErrorMessage: String?

    private let security = SecurityManager.shared
    private let encoder = PacketEncoder()

    private init() {}

    // MARK: - Bonjour Browsing
    func startBrowsing() {
        discoveredServices.removeAll()
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true
        let browser = NWBrowser(for: .bonjour(type: serviceType, domain: nil), using: parameters)
        self.browser = browser
        browser.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .failed(let error):
                DispatchQueue.main.async { self.lastErrorMessage = "Browse failed: \(error)" }
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
            DispatchQueue.main.async {
                self.discoveredServices = newServices.sorted { $0.name < $1.name }
            }
        }
        browser.start(queue: queue)
    }

    // MARK: - Connect
    func connect(to service: DiscoveredService) {
        connectingServiceID = service.id
        lastErrorMessage = nil

        let parameters = NWParameters.tcp
        // Configure TLS
        let options = NWProtocolTLS.Options()
        // Use default TLS; AirBridge should present a certificate. Allow anonymous for LAN if necessary but prefer proper cert.
        sec_protocol_options_set_min_tls_protocol_version(options.securityProtocolOptions, .TLSv12)
        parameters.defaultProtocolStack.applicationProtocols.insert(options, at: 0)

        let connection = NWConnection(to: service.endpoint, using: parameters)
        self.connection = connection

        connection.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .ready:
                DispatchQueue.main.async {
                    self.isConnected = true
                    self.connectingServiceID = nil
                }
                self.postConnectHandshake()
                self.receiveLoop()
            case .failed(let error):
                DispatchQueue.main.async {
                    self.lastErrorMessage = "Connection failed: \(error)"
                    self.isConnected = false
                    self.connectingServiceID = nil
                }
                self.connection?.cancel()
                self.connection = nil
            case .waiting(let error):
                DispatchQueue.main.async { self.lastErrorMessage = "Waiting: \(error)" }
            case .cancelled:
                DispatchQueue.main.async { self.isConnected = false }
            default:
                break
            }
        }

        connection.start(queue: queue)
    }

    func disconnect() {
        connection?.cancel()
        connection = nil
        DispatchQueue.main.async { self.isConnected = false }
    }

    // MARK: - Pairing and Handshake
    private func postConnectHandshake() {
        queue.async { [weak self] in
            guard let self = self else { return }
            do {
                let deviceID = try self.security.getOrCreateDeviceID()
                // If no shared secret, start pairing
                if try self.security.getSharedSecret() == nil {
                    DispatchQueue.main.async { self.isPairing = true }
                    let pairingRequest = [
                        "deviceID": deviceID,
                        "timestamp": ISO8601DateFormatter().string(from: Date()),
                        "type": "pair_request",
                        "payload": [:] as [String: Any]
                    ]
                    try self.sendRawJSON(pairingRequest)
                } else {
                    // Send hello/auth with HMAC to assert possession of secret
                    try self.send(type: "hello", payload: ["deviceID": deviceID])
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
                self.handleIncomingData(data)
            }
            if isComplete || error != nil {
                self.disconnect()
                return
            }
            self.receiveLoop()
        }
    }

    private func handleIncomingData(_ data: Data) {
        // Expect JSON lines or framed JSON. Try to parse as JSON object.
        do {
            let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard let type = obj?["type"] as? String else { return }
            switch type {
            case "pair_response":
                if let secretB64 = obj?["shared_secret"] as? String, let secret = Data(base64Encoded: secretB64) {
                    try? security.storeSharedSecret(secret)
                    DispatchQueue.main.async { self.isPairing = false }
                    // Send hello after pairing
                    try? self.send(type: "hello", payload: ["deviceID": security.currentDeviceID ?? ""]) 
                }
            case "error":
                let message = obj?["message"] as? String ?? "Unknown error"
                DispatchQueue.main.async { self.lastErrorMessage = message }
            default:
                break
            }
        } catch {
            DispatchQueue.main.async { self.lastErrorMessage = "Receive parse error: \(error)" }
        }
    }

    // MARK: - Sending
    private func sendRawJSON(_ object: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [])
        connection?.send(content: data, completion: .contentProcessed { _ in })
    }

    func send(type: String, payload: [String: Any]) throws {
        guard let secret = try security.getSharedSecret(), let deviceID = security.currentDeviceID else {
            throw NSError(domain: "AirPad", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not paired"])
        }
        let packet = try encoder.encodePacket(type: type, payload: payload, deviceID: deviceID, sharedSecret: secret)
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
                self.pendingMouseDelta = (0, 0)
                if abs(delta.dx) > 0.01 || abs(delta.dy) > 0.01 {
                    try? self.send(type: "mouse_move", payload: ["dx": delta.dx, "dy": delta.dy])
                }
            }
            timer.resume()
            mouseMoveTimer = timer
        }
    }

    func sendScroll(dx: Double, dy: Double) {
        try? send(type: "scroll", payload: ["dx": dx, "dy": dy])
    }

    func sendClick(button: String = "left") {
        try? send(type: "mouse_click", payload: ["button": button])
    }

    func sendKeyDown(keyCode: UInt16) {
        try? send(type: "key_down", payload: ["keyCode": Int(keyCode)])
    }

    func sendKeyUp(keyCode: UInt16) {
        try? send(type: "key_up", payload: ["keyCode": Int(keyCode)])
    }
}
