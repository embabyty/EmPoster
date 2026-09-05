//
//  PatreonManager.swift
//  EmPoster
//
//  Patreon-based Pro entitlement, authenticated through the Pocket Poster
//  proxy server (see server/ in the repo). The client secret lives on the
//  server; this app only handles a session token.
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

    /// Whether the logged-in account may moderate community submissions.
    /// Comes from the server's identity (owner + staff).
    @Published private(set) var isAdmin: Bool {
        didSet { UserDefaults.standard.set(isAdmin, forKey: UserDefaultsKey.isAdmin) }
    }

    /// Session token issued by the proxy server.
    @Published private(set) var sessionToken: String? {
        didSet { UserDefaults.standard.set(sessionToken, forKey: UserDefaultsKey.sessionToken) }
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
        static let isAdmin = "patreonIsAdmin"
        static let sessionToken = "patreonSessionToken"
    }

    private init() {
        isPro = UserDefaults.standard.bool(forKey: UserDefaultsKey.isPro)
        isUltra = UserDefaults.standard.bool(forKey: UserDefaultsKey.isUltra)
        isLoggedIn = UserDefaults.standard.bool(forKey: UserDefaultsKey.isLoggedIn)
        memberName = UserDefaults.standard.string(forKey: UserDefaultsKey.memberName)
        memberEmail = UserDefaults.standard.string(forKey: UserDefaultsKey.memberEmail)
        tier = UserDefaults.standard.string(forKey: UserDefaultsKey.tier)
        isAdmin = UserDefaults.standard.bool(forKey: UserDefaultsKey.isAdmin)
        sessionToken = UserDefaults.standard.string(forKey: UserDefaultsKey.sessionToken)

        // Re-validate any cached session with the server.
        if sessionToken != nil {
            Task { await refreshFromServer() }
        }
    }

    // MARK: - Subscribe

    /// Opens the Patreon creator page.
    func subscribe() {
        UIApplication.shared.open(PatreonConfig.profileURL, options: [:], completionHandler: nil)
    }

    // MARK: - Login / Logout

    /// Starts the Patreon OAuth flow through the proxy server.
    func login() {
        guard !isAuthenticating else { return }
        guard let url = ServerConfig.loginURL else {
            lastError = "The proxy server URL is invalid. Check the Server URL in Settings."
            return
        }
        isAuthenticating = true
        UIApplication.shared.open(url, options: [:]) { [weak self] _ in
            self?.isAuthenticating = false
        }
    }

    /// Handles the `pocketposter://patreon` deep link returning from the
    /// server's OAuth callback. The server sends `?token=...` on success or
    /// `?error=...` on failure.
    func handleRedirect(_ url: URL) {
        guard url.scheme?.lowercased() == "pocketposter" else { return }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }

        if let token = components.queryItems?.first(where: { $0.name == "token" })?.value, !token.isEmpty {
            Task { await completeLogin(token: token) }
        } else if let error = components.queryItems?.first(where: { $0.name == "error" })?.value {
            lastError = "Patreon login failed: \(error)"
            UIApplication.shared.alert(title: "Login Failed", body: lastError ?? "")
        }
    }

    /// Calls the server with the session token to load the identity.
    private func completeLogin(token: String) async {
        isAuthenticating = true
        defer { isAuthenticating = false }

        do {
            let me = try await ServerAPI.me(token: token)
            sessionToken = token
            apply(me)
            lastError = nil
            Haptic.shared.notify(.success)

            // Pull community data (approved feed + pending queue for admins).
            await CommunityManager.shared.refreshFromServer()
        } catch {
            lastError = error.localizedDescription
            UIApplication.shared.alert(title: "Login Failed", body: error.localizedDescription)
        }
    }

    /// Re-validates a stored session with the server (e.g. on launch).
    private func refreshFromServer() async {
        guard let token = sessionToken else { return }
        do {
            let me = try await ServerAPI.me(token: token)
            apply(me)
            if isAdmin {
                await CommunityManager.shared.refreshFromServer()
            }
        } catch {
            // Only drop the cached session when the server says it's invalid.
            // If the server is simply unreachable, keep the cached Pro state.
            if case ServerAPIError.serverError(let code) = error, code == 401 {
                sessionToken = nil
                isLoggedIn = false
                isAdmin = false
            }
        }
    }

    private func apply(_ me: ServerMe) {
        isLoggedIn = true
        memberEmail = me.email
        memberName = me.name
        isAdmin = me.isAdmin
        isPro = me.isAdmin
        isUltra = me.isUltra
        tier = me.tier ?? (me.isOwner ? "Owner" : "Staff")
        lastError = nil
    }

    func logOut() {
        if let token = sessionToken {
            Task { await ServerAPI.logout(token: token) }
        }
        sessionToken = nil
        isPro = false
        isUltra = false
        isLoggedIn = false
        memberName = nil
        memberEmail = nil
        tier = nil
        isAdmin = false
        lastError = nil
    }
}