//
//  PacketEncoder.swift
//  AirPad
//
//  Encodes packets as JSON with deviceID, timestamp, type, payload, and HMAC.
//

import Foundation

struct LegacyPacketEncoder {
    func encodePacket(type: String, payload: [String: Any], deviceID: String, sharedSecret: Data) throws -> [String: Any] {
        // Create canonical JSON of payload for HMAC calculation
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let base: [String: Any] = [
            "deviceID": deviceID,
            "timestamp": timestamp,
            "type": type,
            "payload": payload
        ]
        let canonicalData = try JSONSerialization.data(withJSONObject: base, options: [.sortedKeys])
        let hmac = SecurityManager.shared.hmacSHA256(data: canonicalData, key: sharedSecret)
        let hmacB64 = hmac.base64EncodedString()
        var packet = base
        packet["hmac"] = hmacB64
        return packet
    }
}

