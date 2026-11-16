import XCTest
import Network
import Foundation
@testable import AirPad

/// Exercises the real phone NetworkManager. The peer deliberately withholds
/// approval so a TCP/TLS connection cannot masquerade as usable control.
private final class HandshakePeer {
    let queue = DispatchQueue(label: "handshake-test")
    let macID: String
    let legacy: Bool
    private let listener: NWListener
    private var peer: NWConnection?
    private var buffer = Data()
    private var proved = false
    private var port: NWEndpoint.Port?
    init(macID: String, identity: String, key: Data, legacy: Bool = false) throws {
        self.macID = macID; self.legacy = legacy
        listener = try NWListener(using: legacy ? AirSecureChannel.makePSKParameters(psk: AirSecureChannel.stage1PSK, identity: AirSecureChannel.stage1Identity) : WieldSecureTransport.parameters(keys: [identity: key]), on: .any)
        listener.newConnectionHandler = { [weak self] peer in
            guard let self else { return }
            self.peer = peer; peer.start(queue: self.queue); self.receive()
        }
    }
    func start() async throws -> NWEndpoint.Port {
        try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                if case .ready = state, let port = self.listener.port {
                    self.port = port; self.listener.stateUpdateHandler = nil; continuation.resume(returning: port)
                } else if case .failed(let error) = state {
                    self.listener.stateUpdateHandler = nil; continuation.resume(throwing: error)
                }
            }
            listener.start(queue: queue)
        }
    }
    func stop() { queue.async { self.peer?.cancel(); self.listener.cancel() } }
    func proofReceived() async -> Bool { await withCheckedContinuation { c in queue.async { c.resume(returning: self.proved) } } }
    func approve() { queue.async { self.send(["type": self.legacy ? "pong" : "auth_ok", "payload": [:]]) } }
    private func send(_ value: [String: Any]) {
        var data = try! JSONSerialization.data(withJSONObject: value); data.append(10)
        peer?.send(content: data, completion: .contentProcessed { _ in })
    }
    private func receive() {
        peer?.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, complete, error in
            guard let self else { return }
            if let data {
                self.buffer.append(data)
                while let end = self.buffer.firstIndex(of: 10) {
                    let line = Data(self.buffer.prefix(upTo: end)); self.buffer.removeSubrange(...end)
                    let value = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any]
                    if value?["type"] as? String == "hello" {
                        self.send(["type": "server_info", "payload": ["macID": self.macID, "macName": "Test Mac"]])
                        self.send(["type": "auth_challenge", "payload": ["nonce": Data(repeating: 4, count: 32).base64EncodedString()]])
                    } else if value?["type"] as? String == "auth_proof" { self.proved = true }
                }
            }
            if !complete && error == nil { self.receive() }
        }
    }
}

@MainActor
final class RemoteConnectionTests: XCTestCase {
    func testSecureControlWaitsForAuthentication() async throws { try await exercise(legacy: false) }
    func testOlderHostRequiresAuthenticatedPong() async throws { try await exercise(legacy: true) }

    private func exercise(legacy: Bool) async throws {
        let network = NetworkManager.shared
        network.disconnect()
        let id = UUID().uuidString
        let identity = try SecurityManager.shared.getOrCreateDeviceID()
        let secret = Data(repeating: 7, count: 32)
        if legacy { try SecurityManager.shared.storeSharedSecret(secret, forMac: id) }
        else { try SecurityManager.shared.storeSecureSecret(secret, forMac: id) }
        let key = WieldSecureTransport.key(secret: secret, purpose: "control")
        let peer = try HandshakePeer(macID: id, identity: identity, key: key, legacy: legacy)
        defer {
            network.disconnect(); peer.stop()
            SecurityManager.shared.deleteSecureSecret(forMac: id)
            _ = try? SecurityManager.shared.deleteSharedSecret(forMac: id)
        }
        let port = try await peer.start()
        var service = DiscoveredService(name: "Test Mac", host: "127.0.0.1", port: Int(port.rawValue), endpoint: .hostPort(host: "127.0.0.1", port: port))
        if !legacy { service.secureMacID = id; service.secureIdentity = identity; service.secureKey = key }
        network.connect(to: service)
        var proved = false
        for _ in 0..<100 {
            if await peer.proofReceived() { proved = true; break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertTrue(proved, "The real client must complete its proof")
        XCTAssertFalse(network.isConnected, "TLS ready alone must not expose controls")
        peer.approve()
        for _ in 0..<50 {
            if network.isConnected { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertTrue(network.isConnected)
        XCTAssertEqual(network.isSecureConnection, !legacy)
    }

    func testKnownMacMigrationPreservesPairingIdentity() throws {
        let old = Data("[{\"id\":\"existing-mac\",\"name\":\"Mac mini\",\"macAddress\":\"aa:bb:cc:dd:ee:ff\"}]".utf8)
        let records = try JSONDecoder().decode([KnownMac].self, from: old)
        XCTAssertEqual(records.first?.id, "existing-mac")
        XCTAssertNil(records.first?.remoteAddress)
    }
}
