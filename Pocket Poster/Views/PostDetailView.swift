//
//  PostDetailView.swift
//  EmPoster
//
//  Created by lemin on 9/5/25.
//
//  X/Threads-style post detail: the original post with action buttons
//  (comment, repost, like, share), a 3-dot menu, and the comment thread
//  below with an input bar. Pushed from the Home feed, so the system
//  back button returns to the timeline.
//

import SwiftUI

struct PostDetailView: View {
    let submission: TendieSubmission

    @ObservedObject private var likes = LikesManager.shared
    @ObservedObject private var comments = CommentsManager.shared

    @State private var newComment = ""
    @FocusState private var isCommentFieldFocused: Bool

    private var currentAuthor: String {
        PatreonManager.shared.memberName ?? "Guest"
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    postHeader
                    postBody
                    actionBar
                    Divider()
                        .padding(.top, 14)
                    commentsList
                }
            }
            commentInputBar
        }
        .navigationTitle("Post")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Post

    private var postHeader: some View {
        HStack(alignment: .top, spacing: 10) {
            avatar(for: submission.authorName, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(submission.authorName)
                    .font(.subheadline)
                    .fontWeight(.bold)
                Text("@\(submission.authorName) · \(timeAgo(submission.createdAt))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            postMenu
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    private var postMenu: some View {
        Menu {
            ShareLink(item: "Check out this tendie wallpaper: \(submission.title)") {
                Label("Share Post", systemImage: "square.and.arrow.up")
            }
            Button(role: .destructive) {
                Haptic.shared.notify(.error)
                UIApplication.shared.alert(title: "Reported", body: "Thanks for letting us know. We'll take a look.")
            } label: {
                Label("Report", systemImage: "flag")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 18))
                .foregroundStyle(.secondary)
                .padding(6)
        }
    }

    private var postBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !submission.title.isEmpty {
                Text(submission.title)
                    .font(.headline)
            }
            if !submission.description.isEmpty {
                Text(submission.description)
                    .font(.subheadline)
            }
            TendiePreviewImage(
                previewURL: submission.isRemote ? ServerConfig.previewURL(id: submission.id) : nil,
                storedFileName: submission.isRemote ? nil : submission.tendieFiles.first
            )
            .frame(height: 360)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            if !submission.tags.isEmpty {
                HStack(spacing: 8) {
                    ForEach(submission.tags, id: \.self) { tag in
                        Text("#\(tag)")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
    }

    // MARK: - Action Bar

    private var actionBar: some View {
        HStack(spacing: 28) {
            // Comment
            Button {
                isCommentFieldFocused = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "bubble.right")
                    if comments.comments(for: submission.id).count > 0 {
                        Text("\(comments.comments(for: submission.id).count)")
                    }
                }
            }
            // Repost
            Button {
                Haptic.shared.play(.light)
                likes.toggleRepost(submission.id)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.2.squarepath")
                        .foregroundStyle(likes.isReposted(submission.id) ? Color.green : Color.secondary)
                    if likes.isReposted(submission.id) {
                        Text("1")
                            .foregroundStyle(likes.isReposted(submission.id) ? Color.green : Color.secondary)
                    }
                }
            }
            // Like
            Button {
                Haptic.shared.play(.light)
                likes.toggle(submission.id)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: likes.isLiked(submission.id) ? "heart.fill" : "heart")
                        .foregroundStyle(likes.isLiked(submission.id) ? Color.red : Color.secondary)
                    if likes.isLiked(submission.id) {
                        Text("1")
                            .foregroundStyle(likes.isLiked(submission.id) ? Color.red : Color.secondary)
                    }
                }
            }
            Spacer()
            // Share
            ShareLink(item: "Check out this tendie wallpaper: \(submission.title)") {
                Image(systemName: "square.and.arrow.up")
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.top, 14)
    }

    // MARK: - Comments

    @ViewBuilder
    private var commentsList: some View {
        let items = comments.comments(for: submission.id)
        if items.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 30))
                    .foregroundStyle(.secondary)
                Text("No comments yet. Start the conversation!")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
            .padding(.horizontal, 32)
        } else {
            ForEach(items) { comment in
                commentRow(comment)
            }
        }
    }

    private func commentRow(_ comment: Comment) -> some View {
        HStack(alignment: .top, spacing: 10) {
            avatar(for: comment.authorName, size: 32)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(comment.authorName)
                        .font(.caption)
                        .fontWeight(.bold)
                        .lineLimit(1)
                    Text("@\(comment.authorName) · \(timeAgo(comment.createdAt))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    commentMenu(comment)
                }
                Text(comment.text)
                    .font(.subheadline)
                HStack(spacing: 20) {
                    Button {
                        Haptic.shared.play(.light)
                        comments.toggleLike(comment.id)
                    } label: {
                        Image(systemName: comments.isLiked(comment.id) ? "heart.fill" : "heart")
                            .font(.caption)
                            .foregroundStyle(comments.isLiked(comment.id) ? Color.red : Color.secondary)
                    }
                    Text("Reply")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func commentMenu(_ comment: Comment) -> some View {
        Menu {
            if comments.canDelete(comment) {
                Button(role: .destructive) {
                    comments.remove(comment, from: submission.id)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
            Button(role: .destructive) {
                Haptic.shared.notify(.error)
                UIApplication.shared.alert(title: "Reported", body: "Thanks for letting us know. We'll take a look.")
            } label: {
                Label("Report", systemImage: "flag")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(4)
        }
    }

    // MARK: - Input

    private var commentInputBar: some View {
        HStack(spacing: 12) {
            TextField("Add a comment...", text: $newComment, axis: .vertical)
                .lineLimit(1...4)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.secondarySystemBackground), in: Capsule())
                .focused($isCommentFieldFocused)
            Button {
                postComment()
            } label: {
                Text("Post")
                    .fontWeight(.semibold)
            }
            .disabled(newComment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func postComment() {
        let text = newComment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        comments.add(to: submission.id, text: text, author: currentAuthor)
        newComment = ""
        isCommentFieldFocused = false
        Haptic.shared.play(.light)
    }

    // MARK: - Avatar

    private func avatar(for name: String, size: CGFloat) -> some View {
        Circle()
            .fill(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: size, height: size)
            .overlay(
                Text(initials(for: name))
                    .font(.system(size: size * 0.38))
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
            )
    }

    private func initials(for name: String) -> String {
        let parts = name
            .split(separator: " ")
            .prefix(2)
            .compactMap { $0.first.map(String.init) }
        return parts.isEmpty ? "?" : parts.joined()
    }
}