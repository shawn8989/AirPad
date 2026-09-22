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
        // Recompute from scratch rather than only ever setting true: a refund or
        // a revocation discovered by restore() could not otherwise clear the
        // entitlement for the rest of the session.
        var entitled = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == Self.productID,
               transaction.revocationDate == nil {
                entitled = true
            }
        }
        purchased = entitled
        await loadProductIfNeeded()
    }

    /// Fetches the product, retrying on later calls if it failed.
    ///
    /// This used to run only from `init` and `restore()`, and only when
    /// `product == nil`. A first launch without network therefore left `product`
    /// nil for the whole session — and the paywall button is disabled while it
    /// is nil, so Pro could not be bought at all until the app was relaunched.
    func loadProductIfNeeded() async {
        guard product == nil else { return }
        do {
            product = try await Product.products(for: [Self.productID]).first
            if product == nil {
                lastError = "This purchase isn't available yet. Please try again shortly."
            }
        } catch {
            // Not surfaced as an error: the paywall already says "Loading price…"
            // and a retry is one tap away.
            product = nil
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
        do {
            try await AppStore.sync()
        } catch {
            // Cancelling the Apple ID prompt lands here. Reporting "no purchase
            // found" for that is wrong and reads as data loss to someone who
            // has in fact bought Pro.
            lastError = "Restore was cancelled or could not reach the App Store."
            return
        }
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
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecSuccess,
           let data = item as? Data,
           let string = String(data: data, encoding: .utf8),
           let interval = TimeInterval(string) {
            return Date(timeIntervalSince1970: interval)
        }

        // "Not found" and "couldn't read" are different answers, and treating
        // them alike restarted the trial clock. The item is stored
        // AfterFirstUnlock, so a launch before first unlock (a background launch
        // after a reboot) returns errSecInteractionNotAllowed — and the whole
        // session then believed a fresh 7-day trial had just begun, because
        // trialStart is lazy and computed once.
        //
        // When the Keychain is merely unreadable, assume the trial is over: a
        // wrong answer that under-grants is recoverable by relaunching, whereas
        // one that over-grants hands out unlimited free trials.
        if status != errSecItemNotFound {
            return Date.distantPast
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
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        if addStatus == errSecDuplicateItem {
            // Someone else wrote it between our read and our write; theirs wins.
            var existing: CFTypeRef?
            if SecItemCopyMatching(query as CFDictionary, &existing) == errSecSuccess,
               let data = existing as? Data,
               let string = String(data: data, encoding: .utf8),
               let interval = TimeInterval(string) {
                return Date(timeIntervalSince1970: interval)
            }
            return Date.distantPast
        }
        return now
    }
}
