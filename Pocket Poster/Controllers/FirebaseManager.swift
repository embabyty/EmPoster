//
//  FirebaseManager.swift
//  EmPoster
//
//  Created by lemin on 9/5/25.
//
//  Thin wrapper around Firebase (Firestore + Storage + anonymous Auth).
//  Everything is guarded so the app works fully offline / without a
//  GoogleService-Info.plist (submissions just stay local until Firebase
//  is configured).
//

import Foundation
import UIKit
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import GoogleSignIn

@MainActor
final class FirebaseManager: ObservableObject {
    static let shared = FirebaseManager()

    /// True when a GoogleService-Info.plist is present and FirebaseApp
    /// was configured successfully.
    @Published private(set) var isConfigured: Bool

    /// True after anonymous sign-in completed (Firestore/Storage requests
    /// will be authenticated). Starts false if Firebase isn't configured.
    @Published private(set) var isReady = false

    /// True when the current Firebase session is a real Google account
    /// (not anonymous).
    @Published private(set) var isGoogleSignedIn = false

    /// Email / display name of the signed-in Google account, if any.
    var currentUserEmail: String? { Auth.auth().currentUser?.email }
    var currentUserName: String? { Auth.auth().currentUser?.displayName }

    var db: Firestore { Firestore.firestore() }
    var storage: Storage { Storage.storage() }

    private init() {
        let hasConfig = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil
        if hasConfig, FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }
        isConfigured = FirebaseApp.app() != nil
        updateGoogleState()
        if isConfigured {
            Task { await ensureSignedIn() }
        }
    }

    /// Ensures a Firebase session exists (used by rules). If the user has
    /// already signed in with Google, keeps that account.
    func ensureSignedIn() async {
        guard isConfigured else { return }
        updateGoogleState()
        if Auth.auth().currentUser != nil {
            isReady = true
            return
        }

        await withCheckedContinuation { continuation in
            Auth.auth().signInAnonymously { [weak self] _, error in
                if let error {
                    print("Firebase anonymous auth failed: \(error.localizedDescription)")
                }
                self?.isReady = true
                self?.updateGoogleState()
                continuation.resume()
            }
        }
    }

    /// Signs in with a Google account via the Google Sign-In sheet.
    /// If an anonymous session exists, it is upgraded (linked) to the
    /// Google account.
    func signInWithGoogle() async throws {
        guard isConfigured else { throw FirebaseGoogleError.notConfigured }
        guard let clientID = FirebaseApp.app()?.options.clientID, !clientID.isEmpty else {
            throw FirebaseGoogleError.missingClientID
        }
        guard let root = topViewController() else { throw FirebaseGoogleError.noPresenter }

        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)

        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: root)
        guard let idToken = result.user.idToken?.tokenString else {
            throw FirebaseGoogleError.noIDToken
        }
        let credential = GoogleAuthProvider.credential(
            withIDToken: idToken,
            accessToken: result.user.accessToken.tokenString
        )

        if let current = Auth.auth().currentUser, current.isAnonymous {
            try await current.link(with: credential)
        } else {
            try await Auth.auth().signIn(with: credential)
        }
        updateGoogleState()
        isReady = true
    }

    /// Signs out of Firebase entirely.
    func signOutFirebase() {
        try? Auth.auth().signOut()
        updateGoogleState()
        if isConfigured {
            Task { await ensureSignedIn() }
        }
    }

    private func updateGoogleState() {
        let user = Auth.auth().currentUser
        isGoogleSignedIn = user != nil && !(user?.isAnonymous ?? true)
    }

    private func topViewController() -> UIViewController? {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController
                  ?? scene.windows.first?.rootViewController else { return nil }
        var top = root
        while let presented = top.presentedViewController {
            top = presented
        }
        return top
    }

    // MARK: - Storage uploads

    /// Uploads a local file (e.g. a tendie zip) to the given storage path.
    func uploadFile(from url: URL, to path: String) async throws {
        try await withCheckedThrowingContinuation { continuation in
            storage.reference(withPath: path).putFile(from: url, metadata: nil) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    /// Uploads raw data (e.g. a preview thumbnail) to the given storage path.
    func uploadData(_ data: Data, to path: String) async throws {
        try await withCheckedThrowingContinuation { continuation in
            storage.reference(withPath: path).putData(data, metadata: nil) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    /// Resolves a storage path to an HTTPS download URL.
    func downloadURL(forPath path: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            storage.reference(withPath: path).downloadURL { url, error in
                if let url {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(throwing: error ?? URLError(.unknown))
                }
            }
        }
    }
}

/// Errors surfaced during Google Sign-In.
enum FirebaseGoogleError: LocalizedError {
    case notConfigured
    case missingClientID
    case noPresenter
    case noIDToken

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Google Sign-In isn't set up yet. Make sure GoogleService-Info.plist is in the app."
        case .missingClientID:
            return "Google Sign-In isn't configured. Enable the Google provider in the Firebase console, re-download GoogleService-Info.plist, and rebuild."
        case .noPresenter:
            return "Could not present the Google sign-in sheet."
        case .noIDToken:
            return "Google Sign-In didn't return an identity token."
        }
    }
}