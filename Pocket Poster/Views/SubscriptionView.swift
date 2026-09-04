//
//  SubscriptionView.swift
//  Pocket Poster
//
//  Created for StoreKit 2 testing.
//

import SwiftUI
import StoreKit

/// Paywall for "Pocket Poster Pro" — auto-renewable subscriptions.
/// Works with the local `PocketPoster.storekit` configuration in Xcode.
struct SubscriptionView: View {
    @ObservedObject private var store = SubscriptionManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var selectedPlan: Product?
    @State private var errorAlertPresented = false

    private struct FeatureRow: Identifiable {
        let icon: String
        let text: String
        var id: String { text }
    }

    private let featureRows = [
        FeatureRow(icon: "clock.badge.checkmark", text: "Disable the video duration limit"),
        FeatureRow(icon: "film.stack", text: "Apply video wallpapers without restrictions"),
        FeatureRow(icon: "crown.fill", text: "Download Pro-only custom wallpapers"),
        FeatureRow(icon: "star.circle", text: "Support ongoing Pocket Poster development")
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    header

                    if store.isPro {
                        activeCard
                    }

                    featuresCard
                    planCards

                    subscribeButton

                    Button("Restore Purchases") {
                        Task { await store.restorePurchases() }
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .disabled(store.isPurchasing)

                    termsText
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
            }
            .navigationTitle("Pocket Poster Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
            .task {
                await store.loadProducts()
                if selectedPlan == nil {
                    selectedPlan = store.products.first { $0.id == SubscriptionManager.Plan.proYearly }
                        ?? store.products.first
                }
            }
            .onChange(of: store.products) { products in
                if selectedPlan == nil {
                    selectedPlan = products.first { $0.id == SubscriptionManager.Plan.proYearly }
                        ?? products.first
                }
            }
            .alert("Purchase Error", isPresented: $errorAlertPresented) {
                Button("OK", role: .cancel) { store.clearError() }
            } message: {
                if let error = store.lastError {
                    Text(error)
                }
            }
            .onChange(of: store.lastError) { error in
                errorAlertPresented = error != nil
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 12) {
            Image(systemName: "crown.fill")
                .font(.system(size: 56))
                .foregroundStyle(.yellow)
                .padding(.bottom, 4)

            Text("Go Pro")
                .font(.largeTitle)
                .fontWeight(.heavy)

            Text("Unlock the full Pocket Poster experience with an active subscription.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Active Card

    private var activeCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.title2)
                .foregroundStyle(.green)

            VStack(alignment: .leading, spacing: 2) {
                Text(store.isUltra ? "Pocket Poster Ultra is Active" : "Pocket Poster Pro is Active")
                    .font(.headline)
                if let subscription = store.currentSubscription {
                    Text("\(subscription.displayName) — \(subscription.displayPrice)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.green.opacity(0.15))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.green.opacity(0.4), lineWidth: 1.5)
        )
    }

    // MARK: - Features

    private var featuresCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(featureRows) { row in
                HStack(spacing: 12) {
                    Image(systemName: row.icon)
                        .foregroundStyle(.blue)
                        .frame(width: 28)
                    Text(row.text)
                        .font(.subheadline)
                    Spacer()
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
    }

    // MARK: - Plans

    private var planCards: some View {
        VStack(spacing: 20) {
            tierSection(
                title: "Pro",
                subtitle: "Everything you need — video wallpapers, no duration limit, Pro wallpapers.",
                plans: store.products.filter { SubscriptionManager.Plan.proIDs.contains($0.id) }
            )

            tierSection(
                title: "Ultra",
                subtitle: "The complete Pocket Poster experience — includes every Pro feature.",
                plans: store.products.filter { SubscriptionManager.Plan.ultraIDs.contains($0.id) }
            )
        }
    }

    private func tierSection(title: String, subtitle: String, plans: [Product]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.title3)
                    .fontWeight(.bold)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(plans) { product in
                planRow(for: product)
            }
        }
    }

    private func planRow(for product: Product) -> some View {
        let isSelected = selectedPlan?.id == product.id
        let isYearly = product.id == SubscriptionManager.Plan.proYearly
            || product.id == SubscriptionManager.Plan.ultraYearly

        return Button {
            selectedPlan = product
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(product.displayName)
                            .font(.headline)
                            .foregroundStyle(Color(uiColor: .label))

                        if isYearly {
                            Text("BEST VALUE")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.orange.opacity(0.25)))
                                .foregroundStyle(.orange)
                        }
                    }

                    Text("\(product.displayPrice) \(periodLabel(for: product))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? .blue : Color(uiColor: .tertiaryLabel))
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(uiColor: .secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Subscribe Button

    @ViewBuilder
    private var subscribeButton: some View {
        if store.isPro {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                Text("Subscribed")
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .foregroundStyle(.white)
            .background(Capsule().fill(Color.green))
        } else if let plan = selectedPlan {
            Button {
                Task { await store.purchase(plan) }
            } label: {
                HStack(spacing: 8) {
                    if store.isPurchasing {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("Subscribe for \(plan.displayPrice)/\(shortPeriodLabel(for: plan))")
                            .fontWeight(.semibold)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .foregroundStyle(.white)
                .background(Capsule().fill(Color.blue))
            }
            .disabled(store.isPurchasing)
        } else {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
    }

    // MARK: - Helpers

    private func periodLabel(for product: Product) -> String {
        guard let period = product.subscription?.subscriptionPeriod else { return "" }
        switch period.unit {
        case .week:
            return period.value == 1 ? "per week" : "per \(period.value) weeks"
        case .month:
            return period.value == 1 ? "per month" : "per \(period.value) months"
        case .year:
            return period.value == 1 ? "per year" : "per \(period.value) years"
        default:
            return ""
        }
    }

    private func shortPeriodLabel(for product: Product) -> String {
        guard let period = product.subscription?.subscriptionPeriod else { return "" }
        switch period.unit {
        case .week: return "week"
        case .month: return "month"
        case .year: return "year"
        default: return "period"
        }
    }

    private var termsText: some View {
        Text("Payment will be charged to your Apple ID account at the confirmation of purchase. The subscription automatically renews unless it is canceled at least 24 hours before the end of the current period. Manage or cancel your subscription in your Apple ID Account Settings at any time. Pocket Poster is offered on an \"as is\" basis and no refunds are provided for unused portions of a subscription period.")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.center)
    }
}