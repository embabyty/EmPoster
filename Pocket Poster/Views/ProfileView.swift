//
//  ProfileView.swift
//  EmPoster
//
//  Created by lemin on 9/5/25.
//
//  Your profile, styled after x.com's redesigned profile page:
//  banner, overlapping avatar, name + handle, bio, stats and
//  underline tabs for your submitted tendie wallpapers.
//

import SwiftUI

struct ProfileView: View {
    @ObservedObject private var community = CommunityManager.shared
    @ObservedObject private var patreon = PatreonManager.shared

    private enum ProfileTab: String, CaseIterable, Identifiable {
        case all = "Submissions"
        case approved = "Approved"
        case pending = "Pending"
        case rejected = "Rejected"

        var id: String { rawValue }
    }

    @State private var selectedTab: ProfileTab = .all

    /// Submissions made by the logged-in account, newest first.
    private var mySubmissions: [TendieSubmission] {
        let email = patreon.memberEmail?.lowercased()
        return community.submissions
            .filter { submission in
                if let email, let authorEmail = submission.authorEmail?.lowercased() {
                    return authorEmail == email
                }
                // Fallback for local-only submissions that recorded a name.
                if !submission.isRemote, let name = patreon.memberName, !name.isEmpty {
                    return submission.authorName == name
                }
                return false
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var filteredSubmissions: [TendieSubmission] {
        switch selectedTab {
        case .all: mySubmissions
        case .approved: mySubmissions.filter { $0.status == .approved }
        case .pending: mySubmissions.filter { $0.status == .pending }
        case .rejected: mySubmissions.filter { $0.status == .rejected }
        }
    }

    private var displayName: String {
        patreon.memberName ?? (patreon.memberEmail == nil ? "Guest" : "Unnamed")
    }

    private var handle: String {
        patreon.memberEmail.map { String($0.split(separator: "@").first ?? "") } ?? "profile"
    }

    private var bio: String {
        if patreon.memberEmail == nil {
            return "Sign in with Patreon to unlock Pro and submit wallpapers."
        }
        return [
            patreon.tier,
            patreon.isUltra ? "Ultra Member" : nil
        ].compactMap { $0 }.joined(separator: " · ")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    banner
                    header
                    tabBar
                    tabContent
                }
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Banner

    private var banner: some View {
        LinearGradient(
            colors: [.blue, .purple],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .frame(height: 140)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                avatar
                Spacer()
                actionButton
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .font(.title2)
                    .fontWeight(.bold)
                    .lineLimit(1)
                Text("@\(handle)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Text(bio)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            statsRow
        }
        .padding(.horizontal, 16)
        .padding(.top, -42)
    }

    private var avatar: some View {
        Circle()
            .fill(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: 84, height: 84)
            .overlay(
                Image(systemName: "person.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(.white)
            )
            .overlay(
                Circle()
                    .stroke(Color(.systemBackground), lineWidth: 4)
            )
    }

    @ViewBuilder
    private var actionButton: some View {
        if patreon.memberEmail == nil {
            NavigationLink {
                SignInView()
            } label: {
                Text("Sign In")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color(.systemBackground))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.accentColor))
            }
        } else {
            Menu {
                Button {
                    patreon.subscribe()
                } label: {
                    Label("Open Patreon", systemImage: "link")
                }
                Button(role: .destructive) {
                    patreon.logOut()
                } label: {
                    Label("Log Out", systemImage: "rectangle.portrait.and.arrow.right")
                }
            } label: {
                Text("Edit Profile")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.secondary.opacity(0.5))
                    )
            }
        }
    }

    private var statsRow: some View {
        HStack(spacing: 16) {
            stat(count: mySubmissions.count, label: "Submissions")
            stat(count: approvedCount, label: "Approved")
            stat(count: pendingCount, label: "Pending")
            stat(count: rejectedCount, label: "Rejected")
        }
    }

    private func stat(count: Int, label: String) -> some View {
        HStack(spacing: 4) {
            Text("\(count)")
                .font(.subheadline)
                .fontWeight(.bold)
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var approvedCount: Int { mySubmissions.filter { $0.status == .approved }.count }
    private var pendingCount: Int { mySubmissions.filter { $0.status == .pending }.count }
    private var rejectedCount: Int { mySubmissions.filter { $0.status == .rejected }.count }

    // MARK: - Tabs

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(ProfileTab.allCases) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTab = tab
                    }
                } label: {
                    VStack(spacing: 0) {
                        Text(tab.rawValue)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(selectedTab == tab ? Color.primary : Color.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                        Rectangle()
                            .fill(selectedTab == tab ? Color.accentColor : Color.clear)
                            .frame(height: 3)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 12)
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        if filteredSubmissions.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "tray")
                    .font(.system(size: 34))
                    .foregroundStyle(.secondary)
                if patreon.memberEmail == nil {
                    Text("Log in with Patreon in Home to see your submitted wallpapers here.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                } else {
                    Text("No \(selectedTab.rawValue.lowercased()) yet.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 48)
            .padding(.horizontal, 32)
        } else {
            LazyVStack(spacing: 0) {
                ForEach(filteredSubmissions) { submission in
                    submissionRow(submission)
                    Divider()
                }
            }
        }
    }

    private func submissionRow(_ submission: TendieSubmission) -> some View {
        HStack(alignment: .top, spacing: 12) {
            TendiePreviewImage(
                previewURL: submission.isRemote ? ServerConfig.previewURL(id: submission.id) : nil,
                storedFileName: submission.isRemote ? nil : submission.tendieFiles.first
            )
            .frame(width: 56, height: 100)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(submission.title)
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .lineLimit(2)
                Text("@\(submission.authorName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    statusPill(submission.status)
                    Text(timeAgo(submission.createdAt))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func statusPill(_ status: TendieSubmission.Status) -> some View {
        let (text, color): (String, Color) = {
            switch status {
            case .pending: ("Pending", .orange)
            case .approved: ("Approved", .green)
            case .rejected: ("Rejected", .red)
            }
        }()

        return Text(text)
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }
}