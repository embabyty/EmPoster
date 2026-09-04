//
//  PatreonManager.swift
//  EmPoster
//
//  Patreon-based Pro entitlement (replaces StoreKit subscriptions).
//  The Patreon profile / OAuth app is not live yet — fill in PatreonConfig
//  once it exists. Everything is already wired up.
//

import Foundation
import UIKit

enum PatreonConfig {
    // TODO: Replace with your real values once the Patreon profile is live.

    /// Your Patreon creator page, e.g. https://www.patreon.com/YourName
    static let profileURL = URL(string: "https://www.patreon.com/")!

    /// Patreon OAuth client ID (Patreon → My page → Apps & Webhooks → Create client).
    /// Leave empty to show "coming soon" instead of a broken OAuth flow.
    static let clientID = ""

    /// Patreon campaign ID (for verifying pledges via the API).
    static let campaignID = ""

    /// Must match a registered URL scheme; the app already registers `pocketposter`.
    static let redirectURI = "pocketposter://patreon"

    /// Optional: if you host a tiny backend that exchanges the OAuth code for
    /// a token (keeps the client secret server-side), set this to its endpoint.
    static let tokenExchangeURL: URL? = nil
}

@MainActor
final class PatreonManager: ObservableObject {

    static let shared = PatreonManager()

    // MARK: - Published State

    /// Whether the user currently has Pro (Patreon patron active or logged in).
    @Published private(set) var isPro: Bool {
        didSet { UserDefaults.standard.set(isPro, forKey: UserDefaultsKey.isPro) }
    }

    @Published private(set) var isLoggedIn: Bool {
        didSet { UserDefaults.standard.set(isLoggedIn, forKey: UserDefaultsKey.isLoggedIn) }
    }

    @Published private(set) var memberName: String? {
        didSet { UserDefaults.standard.set(memberName, forKey: UserDefaultsKey.memberName) }
    }

    @Published private(set) var tier: String? {
        didSet { UserDefaults.standard.set(tier, forKey: UserDefaultsKey.tier) }
    }

    /// Last Patreon error, if any (cleared after being shown).
    @Published var lastError: String?

    /// True while an OAuth request is in flight.
    @Published private(set) var isAuthenticating = false

    // MARK: - Private

    private enum UserDefaultsKey {
        static let isPro = "isProPatreon"
        static let isLoggedIn = "isLoggedInPatreon"
        static let memberName = "patreonMemberName"
        static let tier = "patreonTier"
    }

    private init() {
        isPro = UserDefaults.standard.bool(forKey: UserDefaultsKey.isPro)
        isLoggedIn = UserDefaults.standard.bool(forKey: UserDefaultsKey.isLoggedIn)
        memberName = UserDefaults.standard.string(forKey: UserDefaultsKey.memberName)
        tier = UserDefaults.standard.string(forKey: UserDefaultsKey.tier)
    }

    /// True once a client ID has been configured.
    var isConfigured: Bool {
        !PatreonConfig.clientID.isEmpty
    }

    // MARK: - Subscribe

    /// Opens the Patreon creator page. Shows a "coming soon" alert until configured.
    func subscribe() {
        guard isConfigured else {
            UIApplication.shared.alert(
                title: "Coming Soon",
                body: "The Patreon profile isn't available yet. Please check back later!"
            )
            return
        }
        UIApplication.shared.open(PatreonConfig.profileURL, options: [:], completionHandler: nil)
    }

    // MARK: - Login / Logout

    /// Starts the Patreon OAuth flow in the browser.
    func login() {
        guard isConfigured else {
            UIApplication.shared.alert(
                title: "Coming Soon",
                body: "Patreon login isn't available yet. Please check back later!"
            )
            return
        }
        guard !isAuthenticating else { return }
        isAuthenticating = true

        var components = URLComponents(string: "https://www.patreon.com/oauth2/authorize")!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: PatreonConfig.clientID),
            URLQueryItem(name: "redirect_uri", value: PatreonConfig.redirectURI),
            URLQueryItem(name: "scope", value: "identity identity.memberships")
        ]

        guard let url = components.url else {
            isAuthenticating = false
            lastError = "Could not build the Patreon login URL."
            return
        }

        UIApplication.shared.open(url, options: [:]) { [weak self] _ in
            self?.isAuthenticating = false
        }
    }

    /// Handles the `pocketposter://patreon` deep link returning from Patreon OAuth.
    func handleRedirect(_ url: URL) {
        guard url.scheme?.lowercased() == "pocketposter" else { return }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }

        if let code = components.queryItems?.first(where: { $0.name == "code" })?.value {
            Task { await completeLogin(code: code) }
        } else if let error = components.queryItems?.first(where: { $0.name == "error" })?.value {
            lastError = "Patreon login failed: \(error)"
            UIApplication.shared.alert(title: "Login Failed", body: lastError ?? "")
        }
    }

    /// Exchanges the OAuth code for a token and verifies the membership.
    /// Requires a backend (or client secret) — until then, we only notify.
    private func completeLogin(code: String) async {
        guard let exchangeURL = PatreonConfig.tokenExchangeURL else {
            UIApplication.shared.alert(
                title: "Login Not Ready",
                body: "Patreon login isn't fully set up yet. Membership verification will be enabled when the profile goes live."
            )
            return
        }

        do {
            // TODO: POST the code to your backend:
            //   var request = URLRequest(url: exchangeURL)
            //   request.httpMethod = "POST"
            //   request.httpBody = "code=\(code)&redirect_uri=\(PatreonConfig.redirectURI)".data(using: .utf8)
            // The backend returns { "access_token": ... }.
            // Then fetch: https://www.patreon.com/api/oauth2/v2/identity?include=memberships
            // and check patron_status == "active_patron" for PatreonConfig.campaignID.
            _ = exchangeURL
            await refreshMembership(accessToken: code)
        } catch {
            lastError = error.localizedDescription
            UIApplication.shared.alert(title: "Login Failed", body: error.localizedDescription)
        }
    }

    /// Verifies an active pledge and updates `isPro`.
    /// Not implemented yet — the backend/token exchange is required. Never grants
    /// Pro without a verified entitlement.
    func refreshMembership(accessToken: String?) async {
        guard let accessToken, !accessToken.isEmpty else { return }

        // TODO: Call the Patreon API once the backend is live:
        //   GET https://www.patreon.com/api/oauth2/v2/identity?include=memberships
        //   Authorization: Bearer <accessToken>
        // Then check the membership for PatreonConfig.campaignID has
        // patron_status == "active_patron" and set:
        //   isLoggedIn = true
        //   isPro = true
        //   memberName = <full_name>
        //   tier = <tier title>
        _ = accessToken
    }

    func logOut() {
        isPro = false
        isLoggedIn = false
        memberName = nil
        tier = nil
        lastError = nil
    }
}