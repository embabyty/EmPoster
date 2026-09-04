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

    /// The app owner's Patreon account email. Logging in with this account
    /// unlocks EmPoster Pro on any device (serial gate covers the owner's
    /// phone separately when the serial is readable).
    static let ownerEmail = "ios11emiry@gmail.com"

    /// Patreon OAuth client ID (Patreon → My page → Apps & Webhooks → Create client).
    /// Leave empty to show "coming soon" instead of a broken OAuth flow.
    static let clientID = ""

    /// Patreon OAuth client secret, embedded on purpose for this personal
    /// sideloaded app. Anyone can see it in the repo, but only the owner's
    /// Patreon account can actually unlock Pro. Rotate it if it leaks.
    static let clientSecret = ""

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

    /// Email of the logged-in Patreon account (used for the owner check).
    @Published private(set) var memberEmail: String? {
        didSet { UserDefaults.standard.set(memberEmail, forKey: UserDefaultsKey.memberEmail) }
    }

    /// Last Patreon error, if any (cleared after being shown).
    @Published var lastError: String?

    /// True while an OAuth request is in flight.
    @Published private(set) var isAuthenticating = false

    /// Whether this install is running on the owner's iPhone (serial-gated).
    /// All Pro features and the subscription UI depend on this.
    @Published private(set) var isDeviceAuthorized = false

    /// True once the device authorization check has run for this launch.
    private var didEvaluateDevice = false

    // MARK: - Access

    /// Whether the logged-in Patreon account is the app owner's.
    var isOwnerAccount: Bool {
        guard let email = memberEmail else { return false }
        return email.lowercased() == PatreonConfig.ownerEmail.lowercased()
    }

    /// Whether Pro is unlocked: owner's Patreon account, or the owner's device.
    var canAccessPro: Bool {
        isOwnerAccount || isDeviceAuthorized
    }

    // MARK: - Private

    private enum UserDefaultsKey {
        static let isPro = "isProPatreon"
        static let isLoggedIn = "isLoggedInPatreon"
        static let memberName = "patreonMemberName"
        static let memberEmail = "patreonMemberEmail"
        static let tier = "patreonTier"
    }

    private init() {
        isPro = UserDefaults.standard.bool(forKey: UserDefaultsKey.isPro)
        isLoggedIn = UserDefaults.standard.bool(forKey: UserDefaultsKey.isLoggedIn)
        memberName = UserDefaults.standard.string(forKey: UserDefaultsKey.memberName)
        memberEmail = UserDefaults.standard.string(forKey: UserDefaultsKey.memberEmail)
        tier = UserDefaults.standard.string(forKey: UserDefaultsKey.tier)
    }

    /// True once a client ID has been configured.
    var isConfigured: Bool {
        !PatreonConfig.clientID.isEmpty && !PatreonConfig.clientSecret.isEmpty
    }

    // MARK: - Device Authorization

    /// Runs the serial-number device check once per launch. If the device is
    /// not the owner's iPhone, Pro is revoked and stays unavailable.
    func evaluateAuthorizedDevice() {
        guard !didEvaluateDevice else { return }
        didEvaluateDevice = true

        Task {
            let authorized = await Task.detached(priority: .userInitiated) {
                DeviceGate.isAuthorizedDevice
            }.value

            isDeviceAuthorized = authorized
            // Only force Pro off when the device is unknown AND no owner
            // Patreon account is logged in (owner unlock survives relaunch).
            if !authorized && !isOwnerAccount {
                isPro = false
                isLoggedIn = false
            }
        }
    }

    /// Blocks non-authorized devices with a friendly alert.
    /// Returns `true` when the device may continue.
    @discardableResult
    private func ensureDeviceAuthorized() -> Bool {
        guard isDeviceAuthorized else {
            UIApplication.shared.alert(
                title: "Not Available",
                body: "EmPoster Pro is only available on the owner's device."
            )
            return false
        }
        return true
    }

    // MARK: - Subscribe

    /// Opens the Patreon creator page. Shows a "coming soon" alert until configured.
    func subscribe() {
        guard ensureDeviceAuthorized() else { return }
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
    /// Available on every device so the owner can sign in anywhere.
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

    /// Exchanges the OAuth code for a token, then verifies the identity.
    /// Pro is only granted to the owner's Patreon account.
    private func completeLogin(code: String) async {
        guard isConfigured else {
            UIApplication.shared.alert(
                title: "Login Not Ready",
                body: "Patreon login isn't fully set up yet. Membership verification will be enabled when the profile goes live."
            )
            return
        }

        isAuthenticating = true
        defer { isAuthenticating = false }

        do {
            let accessToken: String
            if let exchangeURL = PatreonConfig.tokenExchangeURL {
                accessToken = try await exchangeCodeViaBackend(code: code, endpoint: exchangeURL)
            } else {
                accessToken = try await exchangeCodeInApp(code: code)
            }
            await refreshMembership(accessToken: accessToken)
        } catch {
            lastError = error.localizedDescription
            UIApplication.shared.alert(title: "Login Failed", body: error.localizedDescription)
        }
    }

    /// Exchanges the code for an access token via your backend (secret stays server-side).
    private func exchangeCodeViaBackend(code: String, endpoint: URL) async throws -> String {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = "code=\(code)&redirect_uri=\(PatreonConfig.redirectURI)"
        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw PatreonError.tokenExchangeFailed
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = json["access_token"] as? String, !token.isEmpty else {
            throw PatreonError.tokenExchangeFailed
        }
        return token
    }

    /// Exchanges the code for an access token directly (embedded client secret).
    private func exchangeCodeInApp(code: String) async throws -> String {
        var request = URLRequest(url: URL(string: "https://www.patreon.com/api/oauth2/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "redirect_uri", value: PatreonConfig.redirectURI),
            URLQueryItem(name: "client_id", value: PatreonConfig.clientID),
            URLQueryItem(name: "client_secret", value: PatreonConfig.clientSecret)
        ]
        request.httpBody = components.query?.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw PatreonError.tokenExchangeFailed
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = json["access_token"] as? String, !token.isEmpty else {
            throw PatreonError.tokenExchangeFailed
        }
        return token
    }

    /// Fetches the logged-in Patreon identity and grants Pro only to the owner.
    func refreshMembership(accessToken: String?) async {
        guard let accessToken, !accessToken.isEmpty else { return }

        do {
            var request = URLRequest(url: URL(string: "https://www.patreon.com/api/oauth2/v2/identity?fields%5Buser%5D=email,full_name")!)
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw PatreonError.identityFetchFailed
            }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let dataDict = json["data"] as? [String: Any],
                  let attrs = dataDict["attributes"] as? [String: Any] else {
                throw PatreonError.identityFetchFailed
            }

            let email = attrs["email"] as? String
            let name = attrs["full_name"] as? String

            guard let email, email.lowercased() == PatreonConfig.ownerEmail.lowercased() else {
                lastError = "This Patreon account is not authorized for EmPoster Pro."
                UIApplication.shared.alert(
                    title: "Not Authorized",
                    body: "EmPoster Pro is only available for the app owner's Patreon account."
                )
                return
            }

            isLoggedIn = true
            memberEmail = email
            memberName = name
            tier = "Owner"
            isPro = true
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            UIApplication.shared.alert(title: "Login Failed", body: error.localizedDescription)
        }
    }

    func logOut() {
        isPro = false
        isLoggedIn = false
        memberName = nil
        memberEmail = nil
        tier = nil
        lastError = nil
    }
}

/// Errors surfaced during the Patreon OAuth flow.
enum PatreonError: LocalizedError {
    case tokenExchangeFailed
    case identityFetchFailed

    var errorDescription: String? {
        switch self {
        case .tokenExchangeFailed:
            return "Failed to exchange the Patreon login code. Please try again."
        case .identityFetchFailed:
            return "Failed to verify your Patreon account. Please try again."
        }
    }
}