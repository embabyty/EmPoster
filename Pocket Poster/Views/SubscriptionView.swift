//
//  SubscriptionView.swift
//  EmPoster
//
//  Support sheet — EmPoster Pro via Patreon (replaces the StoreKit paywall).
//

import SwiftUI

struct SubscriptionView: View {
    @ObservedObject private var patreon = PatreonManager.shared
    @Environment(\.dismiss) private var dismiss

    private struct FeatureRow: Identifiable {
        let icon: String
        let text: String
        var id: String { text }
    }

    private let featureRows = [
        FeatureRow(icon: "clock.badge.checkmark", text: "Disable the video duration limit"),
        FeatureRow(icon: "film.stack", text: "Apply video wallpapers without restrictions"),
        FeatureRow(icon: "crown.fill", text: "Download Pro-only custom wallpapers"),
        FeatureRow(icon: "bolt.fill", text: "MobileGestalt tweaks (MGA)"),
        FeatureRow(icon: "star.circle", text: "Support ongoing EmPoster development")
    ]

    var body: some View {
        NavigationStack {
            Group {
                if patreon.isDeviceAuthorized {
                    content
                } else {
                    notAvailable
                }
            }
            .navigationTitle("EmPoster Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
            .alert("Patreon Error", isPresented: Binding(
                get: { patreon.lastError != nil },
                set: { if !$0 { patreon.lastError = nil } }
            )) {
                Button("OK", role: .cancel) { patreon.lastError = nil }
            } message: {
                Text(patreon.lastError ?? "")
            }
        }
    }

    // MARK: - Content (authorized device only)

    private var content: some View {
        ScrollView {
            VStack(spacing: 24) {
                header

                if patreon.isPro {
                    activeCard
                }

                featuresCard

                patreonButtons

                termsText
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
    }

    // MARK: - Not Available

    private var notAvailable: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.fill")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
                .padding(.bottom, 4)

            Text("EmPoster Pro is not available on this device.")
                .font(.headline)
                .multilineTextAlignment(.center)

            Text("This subscription is only available on the owner's iPhone.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
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

            Text("Unlock the full EmPoster experience by supporting us on Patreon.")
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
                Text("EmPoster Pro is Active")
                    .font(.headline)
                if let name = patreon.memberName {
                    Text(name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let tier = patreon.tier {
                    Text(tier)
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

    // MARK: - Patreon

    private var patreonButtons: some View {
        VStack(spacing: 12) {
            if !patreon.isPro {
                Button(action: {
                    patreon.subscribe()
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "heart.fill")
                        Text("Subscribe on Patreon")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .foregroundStyle(.white)
                    .background(Capsule().fill(patreonColor))
                }
                .buttonStyle(.plain)

                Text("Already a patron? Log in to unlock Pro.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button(action: {
                    patreon.login()
                }) {
                    HStack(spacing: 8) {
                        if patreon.isAuthenticating {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "person.badge.key")
                            Text("Login with Patreon")
                                .fontWeight(.semibold)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .foregroundStyle(.white)
                    .background(Capsule().fill(Color.blue))
                }
                .buttonStyle(.plain)
                .disabled(patreon.isAuthenticating)
            } else {
                Button(action: {
                    patreon.logOut()
                }) {
                    Text("Log Out")
                        .font(.subheadline)
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var patreonColor: Color {
        Color(red: 0.98, green: 0.26, blue: 0.30)
    }

    // MARK: - Terms

    private var termsText: some View {
        Text("Subscribing on Patreon supports EmPoster development. Pro features are unlocked by logging in with the Patreon account that holds an active pledge. EmPoster is offered on an \"as is\" basis and no refunds are provided.")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.center)
    }
}