//
//  CommentsManager.swift
//  EmPoster
//
//  Created by lemin on 9/5/25.
//
//  Local-only comments for community wallpapers, keyed by submission id,
//  with per-comment likes. Persisted in UserDefaults.
//

import Foundation

struct Comment: Identifiable, Codable {
    var id: String = UUID().uuidString
    var submissionID: String
    var authorName: String
    var text: String
    var createdAt: Date = Date()
}

@MainActor
final class CommentsManager: ObservableObject {
    static let shared = CommentsManager()

    @Published private(set) var commentsBySubmission: [String: [Comment]] = [:]
    @Published private(set) var likedCommentIDs: Set<String> = []

    private let commentsKey = "postComments"
    private let likesKey = "likedCommentIDs"

    private init() {
        load()
    }

    func comments(for submissionID: String) -> [Comment] {
        commentsBySubmission[submissionID] ?? []
    }

    func add(to submissionID: String, text: String, author: String) {
        let comment = Comment(submissionID: submissionID, authorName: author, text: text)
        var list = commentsBySubmission[submissionID] ?? []
        list.append(comment)
        commentsBySubmission[submissionID] = list
        save()
    }

    func remove(_ comment: Comment, from submissionID: String) {
        commentsBySubmission[submissionID]?.removeAll { $0.id == comment.id }
        likedCommentIDs.remove(comment.id)
        save()
    }

    func canDelete(_ comment: Comment) -> Bool {
        comment.authorName == (PatreonManager.shared.memberName ?? "Guest")
    }

    func isLiked(_ commentID: String) -> Bool {
        likedCommentIDs.contains(commentID)
    }

    func toggleLike(_ commentID: String) {
        if likedCommentIDs.contains(commentID) {
            likedCommentIDs.remove(commentID)
        } else {
            likedCommentIDs.insert(commentID)
        }
        save()
    }

    // MARK: - Persistence

    private func load() {
        if let data = UserDefaults.standard.data(forKey: commentsKey),
           let decoded = try? JSONDecoder().decode([String: [Comment]].self, from: data) {
            commentsBySubmission = decoded
        }
        if let data = UserDefaults.standard.data(forKey: likesKey),
           let decoded = try? JSONDecoder().decode(Set<String>.self, from: data) {
            likedCommentIDs = decoded
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(commentsBySubmission) {
            UserDefaults.standard.set(data, forKey: commentsKey)
        }
        if let data = try? JSONEncoder().encode(likedCommentIDs) {
            UserDefaults.standard.set(data, forKey: likesKey)
        }
    }
}