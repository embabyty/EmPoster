//
//  PatreonManager.swift
//  EmPoster
//
//  Patreon-based Pro entitlement (replaces StoreKit subscriptions).
//  Only the app owner's Patreon account (ios11emiry@gmail.com) unlocks Pro.
//

import Foundation
import UIKit

enum PatreonConfig {
    /// The app owner's Patreon page.
    static let profileURL = URL(string: "https://www.patreon.com/c/EmAppleFlagship")!

    /// Only this Patreon account email can unlock EmPoster Pro.
    static let ownerEmail = "ios11emiry@gmail.com"

    /// Additional Patreon accounts allowed to log in as staff.
    /// Staff members can approve/reject community wallpaper submissions
    /// (they also get Pro while logged in).
    static let staffEmails: [String] = [
        // e.g. "staff@example.com"
    ]

    /// Patreon OAuth client ID (Patreon → My page → Apps & Webhooks → Create client).
    static let clientID = "A3WtRmw4CkNkPw1zEMvmg38GYiCn5VdtRs0v5Ej01PKT-VtMv924XIvhtwajaV_W"

    /// Patreon OAuth client secret. Embedded on purpose for this personal
    /// sideloaded app — anyone can read it, but only the owner's Patreon
    /// account can actually unlock Pro. Rotate it if it leaks.
    static let clientSecret = "gl_YYkeIu4lUhkh92x382QuxdlliGUbx0ka6q1654jx331SNoaHBO2XYSfL8QIDx"

    /// Patreon campaign ID (for verifying pledges via the API).
    static let campaignID = ""

    /// Patreon redirect URI. Must match exactly what is registered in the
    /// Patreon OAuth app, and the callback URL passed during login.
    /// Patreon only accepts http(s):// URIs, so this lands on a GitHub Pages
    /// bounce page (docs/patreon-callback.html) that forwards the code back
    /// into the app through the `pocketposter://` URL scheme.
    static let redirectURI = "https://embabyty.github.io/EmPoster/patreon-callback.html"

    /// Optional: if you host a tiny backend that exchanges the OAuth code for
    /// a token (keeps the client secret server-side), set this to its endpoint.
    static let tokenExchangeURL: URL? = nil
}

@MainActor
final class PatreonManager: ObservableObject {

    static let shared = PatreonManager()

    // MARK: - Published State

    /// Whether the user currently has Pro (owner's Patreon account logged in).
    @Published private(set) var isPro: Bool {
        didSet { UserDefaults.standard.set(isPro, forKey: UserDefaultsKey.isPro) }
    }

    /// Whether the logged-in patron has pledged at the Ultra tier.
    /// Ultra unlocks everything Pro does (isPro is also set to true).
    @Published private(set) var isUltra: Bool {
        didSet { UserDefaults.standard.set(isUltra, forKey: UserDefaultsKey.isUltra) }
    }

    @Published private(set) var isLoggedIn: Bool {
        didSet { UserDefaults.standard.set(isLoggedIn, forKey: UserDefaultsKey.isLoggedIn) }
    }

    @Published private(set) var memberName: String? {
        didSet { UserDefaults.standard.set(memberName, forKey: UserDefaultsKey.memberName) }
    }

    /// Email of the logged-in Patreon account (used for the owner check).
    @Published private(set) var memberEmail: String? {
        didSet { UserDefaults.standard.set(memberEmail, forKey: UserDefaultsKey.memberEmail) }
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
        static let isUltra = "isUltraPatreon"
        static let isLoggedIn = "isLoggedInPatreon"
        static let memberName = "patreonMemberName"
        static let memberEmail = "patreonMemberEmail"
        static let tier = "patreonTier"
    }

    private init() {
        isPro = UserDefaults.standard.bool(forKey: UserDefaultsKey.isPro)
        isUltra = UserDefaults.standard.bool(forKey: UserDefaultsKey.isUltra)
        isLoggedIn = UserDefaults.standard.bool(forKey: UserDefaultsKey.isLoggedIn)
        memberName = UserDefaults.standard.string(forKey: UserDefaultsKey.memberName)
        memberEmail = UserDefaults.standard.string(forKey: UserDefaultsKey.memberEmail)
        tier = UserDefaults.standard.string(forKey: UserDefaultsKey.tier)
    }

    /// True once a client ID and secret have been configured.
    var isConfigured: Bool {
        !PatreonConfig.clientID.isEmpty && !PatreonConfig.clientSecret.isEmpty
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
    /// If the patron's pledge tier is "Ultra", the Ultra tier is unlocked too.
    func refreshMembership(accessToken: String?) async {
        guard let accessToken, !accessToken.isEmpty else { return }

        do {
            var request = URLRequest(url: URL(string: "https://www.patreon.com/api/oauth2/v2/identity?include=memberships&fields%5Buser%5D=email,full_name&fields%5Bmember%5D=currently_entitled_amount_cents&fields%5Btier%5D=title")!)
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

            guard let email else {
                lastError = "This Patreon account is not authorized for EmPoster."
                UIApplication.shared.alert(
                    title: "Not Authorized",
                    body: "Only the app owner and approved staff Patreon accounts can use EmPoster."
                )
                return
            }

            let isOwner = email.lowercased() == PatreonConfig.ownerEmail.lowercased()
            let isStaff = PatreonConfig.staffEmails.contains(email.lowercased())
            guard isOwner || isStaff else {
                lastError = "This Patreon account is not authorized for EmPoster."
                UIApplication.shared.alert(
                    title: "Not Authorized",
                    body: "Only the app owner and approved staff Patreon accounts can use EmPoster."
                )
                return
            }

            // Read the pledge tier from the Patreon membership so a patron who
            // joined the Ultra tier on the Patreon page unlocks Ultra in-app.
            let tierTitle = membershipTierTitle(from: json)

            isLoggedIn = true
            memberEmail = email
            memberName = name
            isPro = true
            isUltra = tierTitle?.localizedCaseInsensitiveContains("ultra") == true
            tier = isUltra ? (tierTitle ?? "Ultra") : "Owner"
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            UIApplication.shared.alert(title: "Login Failed", body: error.localizedDescription)
        }
    }

    /// Extracts the title of the campaign tier the patron is entitled to
    /// (e.g. "Ultra") from the Patreon identity response.
    private func membershipTierTitle(from json: [String: Any]) -> String? {
        guard let included = json["included"] as? [[String: Any]] else { return nil }

        // The membership relationship points at the entitled tier.
        var tierID: String?
        for item in included where (item["type"] as? String) == "member" {
            guard let relationships = item["relationships"] as? [String: Any],
                  let tier = relationships["tier"] as? [String: Any],
                  let data = tier["data"] as? [String: Any],
                  let id = data["id"] as? String else { continue }
            tierID = id
            break
        }

        guard let tierID else { return nil }
        for item in included where (item["type"] as? String) == "tier" && (item["id"] as? String) == tierID {
            if let attrs = item["attributes"] as? [String: Any],
               let title = attrs["title"] as? String {
                return title
            }
        }
        return nil
    }

    func logOut() {
        isPro = false
        isUltra = false
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