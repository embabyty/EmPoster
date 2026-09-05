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
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage

@MainActor
final class FirebaseManager: ObservableObject {
    static let shared = FirebaseManager()

    /// True when a GoogleService-Info.plist is present and FirebaseApp
    /// was configured successfully.
    @Published private(set) var isConfigured: Bool

    /// True after anonymous sign-in completed (Firestore/Storage requests
    /// will be authenticated). Starts false if Firebase isn't configured.
    @Published private(set) var isReady = false

    /// Email / display name of the signed-in user, if any
    /// (anonymous users have no email or display name).
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
        if isConfigured {
            Task { await ensureSignedIn() }
        }
    }

    /// Ensures a Firebase session exists (used by rules). Signs in
    /// anonymously if there's no session yet.
    func ensureSignedIn() async {
        guard isConfigured else { return }
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
                continuation.resume()
            }
        }
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