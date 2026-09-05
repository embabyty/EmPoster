//
//  SignInView.swift
//  EmPoster
//
//  Created by lemin on 9/5/25.
//
//  Dedicated sign-in page. Users can sign in with Google (Firebase) or
//  sign in / subscribe via Patreon.
//

import SwiftUI

struct SignInView: View {
    @ObservedObject private var firebase = FirebaseManager.shared
    @ObservedObject private var patreon = PatreonManager.shared

    @Environment(\.dismiss) private var dismiss

    @State private var isGoogleLoading = false
    @State private var googleError: String?
    @State private var showSubscription = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 26) {
                    header

                    if firebase.isGoogleSignedIn || patreon.isLoggedIn {
                        currentAccountCard
                    }

                    googleSection

                    orDivider

                    patreonSection

                    Text("Signing in lets you submit wallpapers under your name and manage your EmPoster account. Pro features unlock with a Patreon login of an active patron.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
            }
            .navigationTitle("Sign In")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
            .sheet(isPresented: $showSubscription) {
                SubscriptionView()
            }
            .alert("Google Sign-In Error", isPresented: Binding(
                get: { googleError != nil },
                set: { if !$0 { googleError = nil } }
            )) {
                Button("OK", role: .cancel) { googleError = nil }
            } message: {
                Text(googleError ?? "")
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

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.crop.circle.badge.checkmark")
                .font(.system(size: 56))
                .foregroundStyle(.blue)
                .padding(.bottom, 4)

            Text("Welcome")
                .font(.largeTitle)
                .fontWeight(.heavy)

            Text("Sign in to unlock EmPoster and share your wallpapers.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Current account

    private var currentAccountCard: some View {
        VStack(spacing: 8) {
            if patreon.isLoggedIn {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.title2)
                        .foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Patreon · Pro Active")
                            .font(.headline)
                        Text([
                            patreon.memberName,
                            patreon.tier
                        ].compactMap { $0 }.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
            if firebase.isGoogleSignedIn {
                HStack(spacing: 12) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.blue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Signed in with Google")
                            .font(.headline)
                        Text([
                            firebase.currentUserName,
                            firebase.currentUserEmail
                        ].compactMap { $0 }.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.green.opacity(0.12))
        )
    }

    // MARK: - Google

    private var googleSection: some View {
        VStack(spacing: 12) {
            Text("Continue with Google")
                .font(.subheadline)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity, alignment: .leading)

            if firebase.isGoogleSignedIn {
                Button(action: {
                    firebase.signOutFirebase()
                }) {
                    Text("Sign Out of Google")
                        .font(.subheadline)
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            } else {
                Button(action: {
                    signInWithGoogle()
                }) {
                    HStack(spacing: 10) {
                        if isGoogleLoading {
                            ProgressView()
                        } else {
                            ZStack {
                                Circle()
                                    .fill(Color(red: 0.36, green: 0.58, blue: 0.93))
                                Text("G")
                                    .font(.headline)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.white)
                            }
                            .frame(width: 22, height: 22)
                        }
                        Text("Sign in with Google")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .foregroundStyle(Color(uiColor: .label))
                    .background(
                        Capsule()
                            .fill(Color(uiColor: .secondarySystemBackground))
                            .overlay(Capsule().stroke(Color(uiColor: .separator), lineWidth: 1))
                    )
                }
                .buttonStyle(.plain)
                .disabled(isGoogleLoading)
            }
        }
    }

    private func signInWithGoogle() {
        isGoogleLoading = true
        Task {
            defer { isGoogleLoading = false }
            do {
                try await firebase.signInWithGoogle()
                Haptic.shared.notify(.success)
            } catch {
                googleError = error.localizedDescription
                Haptic.shared.notify(.error)
            }
        }
    }

    // MARK: - Patreon

    private var patreonSection: some View {
        VStack(spacing: 12) {
            Text("Patreon")
                .font(.subheadline)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity, alignment: .leading)

            if patreon.isLoggedIn {
                Button(action: {
                    patreon.logOut()
                }) {
                    Text("Log Out of Patreon")
                        .font(.subheadline)
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            } else {
                Button(action: {
                    patreon.login()
                }) {
                    HStack(spacing: 8) {
                        if patreon.isAuthenticating {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "person.badge.key")
                            Text("Sign into Patreon")
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

                Button(action: {
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                    showSubscription = true
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "heart.fill")
                        Text("Subscribe on Patreon")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .foregroundStyle(.white)
                    .background(Capsule().fill(Color(red: 0.98, green: 0.26, blue: 0.30)))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Divider

    private var orDivider: some View {
        HStack(spacing: 12) {
            Rectangle().fill(Color(uiColor: .separator)).frame(height: 1)
            Text("or")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Rectangle().fill(Color(uiColor: .separator)).frame(height: 1)
        }
    }
}