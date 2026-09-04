//
//  SubscriptionManager.swift
//  Pocket Poster
//
//  Created for StoreKit 2 testing.
//

import Foundation
import StoreKit

/// Manages the "Pocket Poster Pro" and "Pocket Poster Ultra" auto-renewable
/// subscriptions via StoreKit 2.
///
/// Product IDs must match `PocketPoster.storekit` (local StoreKit testing)
/// and, later, the App Store Connect products.
@MainActor
final class SubscriptionManager: ObservableObject {

    static let shared = SubscriptionManager()

    // MARK: - Product Identifiers

    enum Plan {
        // Pocket Poster Pro
        static let proMonthly = "com.mak5er.Pocket-Poster.pro.monthly"
        static let proYearly = "com.mak5er.Pocket-Poster.pro.yearly"
        static let proIDs: [String] = [proMonthly, proYearly]

        // Pocket Poster Ultra
        static let ultraMonthly = "com.mak5er.Pocket-Poster.ultra.monthly"
        static let ultraYearly = "com.mak5er.Pocket-Poster.ultra.yearly"
        static let ultraIDs: [String] = [ultraMonthly, ultraYearly]

        static let all: [String] = proIDs + ultraIDs
    }

    // MARK: - Published State

    /// All subscription products, loaded from the Store.
    @Published private(set) var products: [Product] = []

    /// Whether any active "Pocket Poster Pro" entitlement exists
    /// (Pro, or the higher Ultra tier which includes Pro).
    @Published private(set) var isPro: Bool {
        didSet { UserDefaults.standard.set(isPro, forKey: UserDefaultsKey.isPro) }
    }

    /// Whether an active "Pocket Poster Ultra" entitlement exists.
    @Published private(set) var isUltra: Bool {
        didSet { UserDefaults.standard.set(isUltra, forKey: UserDefaultsKey.isUltra) }
    }

    /// The current subscription product (if any), used to show status in the UI.
    @Published private(set) var currentSubscription: Product?

    /// Last purchase/restore error, if any (cleared after being shown).
    @Published var lastError: String?

    /// True while a purchase/restore request is in flight.
    @Published private(set) var isPurchasing = false

    // MARK: - Private

    private enum UserDefaultsKey {
        static let isPro = "isProCached"
        static let isUltra = "isUltraCached"
    }

    private var transactionUpdatesTask: Task<Void, Never>?

    // MARK: - Init

    init() {
        // Start from the cached entitlement so the UI is correct immediately.
        self.isPro = UserDefaults.standard.bool(forKey: UserDefaultsKey.isPro)
        self.isUltra = UserDefaults.standard.bool(forKey: UserDefaultsKey.isUltra)

        // Listen for transaction updates (renewals, refunds, family sharing…)
        // while the app is running.
        transactionUpdatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                await self?.handle(update)
            }
        }

        Task {
            await loadProducts()
            await refreshEntitlements()
        }
    }

    deinit {
        transactionUpdatesTask?.cancel()
    }

    // MARK: - Loading

    /// Loads the subscription products from the StoreKit configuration.
    func loadProducts() async {
        do {
            let loaded = try await Product.products(for: Plan.all)
            // Order: pro monthly, pro yearly, ultra monthly, ultra yearly.
            products = Plan.all.compactMap { id in loaded.first { $0.id == id } }
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Purchasing

    /// Purchases the given product. Finishes the transaction and refreshes entitlements.
    func purchase(_ product: Product) async {
        isPurchasing = true
        defer { isPurchasing = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    await transaction.finish()
                    await refreshEntitlements()
                case .unverified:
                    lastError = "The purchase could not be verified."
                }
            case .pending:
                // Ask-to-buy or billing agreement — the transaction will arrive via
                // Transaction.updates when it is resolved.
                break
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Restoring

    /// Restores previous purchases (e.g. reinstallation) and refreshes entitlements.
    func restorePurchases() async {
        isPurchasing = true
        defer { isPurchasing = false }

        do {
            try await AppStore.sync()
            await refreshEntitlements()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func clearError() {
        lastError = nil
    }

    // MARK: - Entitlements

    /// Refreshes the Pro/Ultra status from the currently held entitlements.
    func refreshEntitlements() async {
        var subscriptionProductID: String?

        for await entitlement in Transaction.currentEntitlements {
            guard case .verified(let transaction) = entitlement else { continue }
            guard transaction.productType == .autoRenewable,
                  transaction.revocationDate == nil else { continue }

            // The subscription is active if it has no expiration date or is not expired.
            if let expirationDate = transaction.expirationDate {
                guard expirationDate > Date() else { continue }
            }

            // Prefer Ultra when checking so it wins over Pro if both are somehow active.
            if Plan.ultraIDs.contains(transaction.productID) {
                subscriptionProductID = transaction.productID
                break
            }

            if Plan.all.contains(transaction.productID) {
                subscriptionProductID = transaction.productID
                break
            }
        }

        isPro = subscriptionProductID != nil
        isUltra = subscriptionProductID.map { Plan.ultraIDs.contains($0) } ?? false
        currentSubscription = products.first { $0.id == subscriptionProductID }
    }

    // MARK: - Transaction Updates

    /// Finishes and reacts to a transaction update (renewal, refund, etc.).
    private func handle(_ update: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = update else { return }
        await transaction.finish()
        await refreshEntitlements()
    }
}