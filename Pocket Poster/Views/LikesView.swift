//
//  LikesView.swift
//  EmPoster
//
//  Created by lemin on 9/5/25.
//
//  Instagram-style activity list for the submissions you liked.
//  Opened from the heart button on the Home toolbar.
//

import SwiftUI

struct LikesView: View {
    @ObservedObject private var community = CommunityManager.shared
    @ObservedObject private var likes = LikesManager.shared

    private var liked: [TendieSubmission] {
        likes.likedSubmissions(community.submissions)
    }

    var body: some View {
        List {
            if liked.isEmpty {
                emptyState
            } else {
                ForEach(liked) { submission in
                    likeRow(submission)
                }
            }
        }
        .navigationTitle("Likes")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Row

    private func likeRow(_ submission: TendieSubmission) -> some View {
        HStack(spacing: 12) {
            avatar(for: submission.authorName)
                .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text("You liked")
                        .foregroundStyle(.secondary)
                    Text("@\(submission.authorName)'s wallpaper")
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                }
                .lineLimit(2)
                Text(timeAgo(likes.likedAt[submission.id] ?? submission.createdAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            TendiePreviewImage(
                previewURL: submission.isRemote ? ServerConfig.previewURL(id: submission.id) : nil,
                storedFileName: submission.isRemote ? nil : submission.tendieFiles.first
            )
            .frame(width: 56, height: 100)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding(.vertical, 4)
    }

    private func avatar(for name: String) -> some View {
        Circle()
            .fill(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(
                Text(initials(for: name))
                    .font(.subheadline)
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

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "heart")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("No Likes Yet")
                .font(.headline)
            Text("Tap the heart on any wallpaper in your Home feed to like it. It'll show up here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .padding(.horizontal, 32)
    }
}