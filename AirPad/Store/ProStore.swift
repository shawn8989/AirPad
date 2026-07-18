//
//  ProStore.swift
//  AirPad
//
//  AirPad Pro entitlement: StoreKit 2 one-time lifetime unlock + a 7-day
//  full-featured trial. The trial start date lives in the Keychain so
//  deleting and reinstalling the app doesn't reset the clock.
//
//  Pro features: Air Mouse, Hand Mouse, Media & System remote, voice typing,
//  Live Screen, Apps, and multi-Mac switching. Trackpad, keyboard, and the
//  first Mac are free forever.
//

import Foundation
import Combine
import StoreKit
import Security

@MainActor
final class ProStore: ObservableObject {
    static let shared = ProStore()

    static let productID = "com.airpad.pro.lifetime"
    static let trialDays = 7

    @Published private(set) var purchased = false
    @Published private(set) var product: Product?
    @Published var lastError: String?

    private var updatesTask: Task<Void, Never>?

    // MARK: - Entitlement

    var isPro: Bool {
        #if DEBUG
        // Developer builds are always Pro so your own devices never lock after
        // the trial. Flip "Simulate Free" in Settings (DEBUG section) to test
        // the paywall and lock badges.
        if !UserDefaults.standard.bool(forKey: "debug.simulateFree") { return true }
        #endif
        return purchased || inTrial
    }
    var inTrial: Bool { Date() < trialEnd }
    var trialEnd: Date { trialStart.addingTimeInterval(TimeInterval(Self.trialDays) * 86_400) }
    var trialDaysLeft: Int { max(0, Int(ceil(trialEnd.timeIntervalSinceNow / 86_400))) }

    private init() {
        _ = trialStart  // establish the trial clock on first launch
        updatesTask = Task { await listenForTransactions() }
        Task { await refresh() }
    }

    // MARK: - StoreKit

    func refresh() async {
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == Self.productID,
               transaction.revocationDate == nil {
                purchased = true
            }
        }
        if product == nil {
            product = try? await Product.products(for: [Self.productID]).first
        }
    }

    func purchase() async {
        guard let product else {
            lastError = "Store not available right now. Check your connection and try again."
            return
        }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    purchased = true
                    await transaction.finish()
                }
            case .userCancelled, .pending:
                break
            @unknown default:
                break
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func restore() async {
        try? await AppStore.sync()
        await refresh()
        if !purchased {
            lastError = "No previous purchase found for this Apple ID."
        }
    }

    private func listenForTransactions() async {
        for await result in Transaction.updates {
            if case .verified(let transaction) = result {
                if transaction.productID == Self.productID && transaction.revocationDate == nil {
                    purchased = true
                }
                await transaction.finish()
            }
        }
    }

    // MARK: - Trial clock (Keychain-backed)

    private static let trialService = "com.airpad.trial"
    private static let trialAccount = "trial_start"

    private lazy var trialStart: Date = Self.loadOrCreateTrialStart()

    private static func loadOrCreateTrialStart() -> Date {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: trialService,
            kSecAttrAccount as String: trialAccount,
            kSecReturnData as String: true
        ]
        var item: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
           let data = item as? Data,
           let string = String(data: data, encoding: .utf8),
           let interval = TimeInterval(string) {
            return Date(timeIntervalSince1970: interval)
        }
        let now = Date()
        let value = String(now.timeIntervalSince1970).data(using: .utf8)!
        let add: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: trialService,
            kSecAttrAccount as String: trialAccount,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecValueData as String: value
        ]
        SecItemAdd(add as CFDictionary, nil)
        return now
    }
}
