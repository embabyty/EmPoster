//
//  LikesManager.swift
//  EmPoster
//
//  Created by lemin on 9/5/25.
//
//  Local-only engagement for community wallpapers: likes and reposts.
//  Persisted in UserDefaults.
//

import Foundation

@MainActor
final class LikesManager: ObservableObject {
    static let shared = LikesManager()

    /// Submission id -> when it was liked, newest first when listed.
    @Published private(set) var likedAt: [String: Date] = [:]

    /// Submission id -> when it was reposted.
    @Published private(set) var repostedAt: [String: Date] = [:]

    private let likesKey = "likedSubmissions"
    private let repostsKey = "repostedSubmissions"

    private init() {
        load()
    }

    var count: Int { likedAt.count }

    func isLiked(_ id: String) -> Bool {
        likedAt[id] != nil
    }

    func toggle(_ id: String) {
        if likedAt[id] != nil {
            likedAt.removeValue(forKey: id)
        } else {
            likedAt[id] = Date()
        }
        save()
    }

    /// Returns the liked submissions, newest liked first.
    func likedSubmissions(_ submissions: [TendieSubmission]) -> [TendieSubmission] {
        submissions
            .filter { likedAt[$0.id] != nil }
            .sorted { (likedAt[$0.id] ?? .distantPast) > (likedAt[$1.id] ?? .distantPast) }
    }

    func isReposted(_ id: String) -> Bool {
        repostedAt[id] != nil
    }

    func toggleRepost(_ id: String) {
        if repostedAt[id] != nil {
            repostedAt.removeValue(forKey: id)
        } else {
            repostedAt[id] = Date()
        }
        save()
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: likesKey),
           let decoded = try? JSONDecoder().decode([String: Date].self, from: data) {
            likedAt = decoded
        }
        if let data = UserDefaults.standard.data(forKey: repostsKey),
           let decoded = try? JSONDecoder().decode([String: Date].self, from: data) {
            repostedAt = decoded
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(likedAt) {
            UserDefaults.standard.set(data, forKey: likesKey)
        }
        if let data = try? JSONEncoder().encode(repostedAt) {
            UserDefaults.standard.set(data, forKey: repostsKey)
        }
    }
}