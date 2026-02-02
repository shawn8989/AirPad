//
//  SecurityManager.swift
//  AirPad
//
//  Manages persistent deviceID, Keychain storage, and HMAC-SHA256 utilities.
//

import Foundation
import CryptoKit
import Security

final class SecurityManager {
    static let shared = SecurityManager()

    private let deviceIDKey = "airpad.deviceID"
    private let keychainService: String = {
        if let bundleID = Bundle.main.bundleIdentifier, !bundleID.isEmpty {
            return bundleID
        }
        return "com.example.AirPad"
    }()
    private let sharedSecretAccount = "shared_secret"
    private let serverCertFingerprintAccount = "server_cert_fingerprint"

    private(set) var currentDeviceID: String?

    private init() {
        currentDeviceID = UserDefaults.standard.string(forKey: deviceIDKey)
    }

    // MARK: - Device ID
    func getOrCreateDeviceID() throws -> String {
        if let id = currentDeviceID { return id }
        let newID = UUID().uuidString
        UserDefaults.standard.set(newID, forKey: deviceIDKey)
        currentDeviceID = newID
        return newID
    }

    // MARK: - Keychain Shared Secret
    func storeSharedSecret(_ secret: Data) throws {
        // Remove existing
        _ = try? deleteSharedSecret()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: sharedSecretAccount,
            kSecValueData as String: secret,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [NSLocalizedDescriptionKey: "Keychain add failed: \(status)"])
        }
    }

    func getSharedSecret() throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: sharedSecretAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [NSLocalizedDescriptionKey: "Keychain read failed: \(status)"])
        }
        return data
    }

    @discardableResult
    func deleteSharedSecret() throws -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: sharedSecretAccount
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status == errSecItemNotFound { return false }
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [NSLocalizedDescriptionKey: "Keychain delete failed: \(status)"])
        }
        return true
    }

    // MARK: - Server certificate pinning
    func storeServerCertFingerprint(_ fingerprint: Data) throws {
        // Remove existing
        _ = try? deleteServerCertFingerprint()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: serverCertFingerprintAccount,
            kSecValueData as String: fingerprint,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [NSLocalizedDescriptionKey: "Keychain add failed: \(status)"])
        }
    }

    func getServerCertFingerprint() throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: serverCertFingerprintAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [NSLocalizedDescriptionKey: "Keychain read failed: \(status)"])
        }
        return data
    }

    @discardableResult
    func deleteServerCertFingerprint() throws -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: serverCertFingerprintAccount
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status == errSecItemNotFound { return false }
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [NSLocalizedDescriptionKey: "Keychain delete failed: \(status)"])
        }
        return true
    }

    // MARK: - HMAC
    func hmacSHA256(data: Data, key: Data) -> Data {
        let keySym = SymmetricKey(data: key)
        let mac = HMAC<SHA256>.authenticationCode(for: data, using: keySym)
        return Data(mac)
    }
}

