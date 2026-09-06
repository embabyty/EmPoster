//
//  ContentView.swift
//  EmPoster
//
//  Created by lemin on 5/31/25.
//
//  Home: an x.com-style feed of community tendie wallpapers.
//  The Tendies actions live in the popup menu next to Settings,
//  and the avatar top-left jumps straight to the Profile tab.
//

import SwiftUI
import UniformTypeIdentifiers

extension UIDocumentPickerViewController {
    @objc func fix_init(forOpeningContentTypes contentTypes: [UTType], asCopy: Bool) -> UIDocumentPickerViewController {
        return fix_init(forOpeningContentTypes: contentTypes, asCopy: true)
    }
}

struct ContentView: View {
    @ObservedObject private var community = CommunityManager.shared
    @ObservedObject private var likes = LikesManager.shared
    @ObservedObject var pbManager = PosterBoardManager.shared

    @Binding var selectedTab: Int

    @AppStorage("pbHash") var pbHash: String = ""

    @State var showTendiesImporter: Bool = false

    private let profileTab = 5

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 0) {
                    if community.approved.isEmpty {
                        emptyFeed
                    } else {
                        ForEach(community.approved) { submission in
                            FeedPostCard(submission: submission) {
                                addToTendies(submission)
                            }
                            Divider()
                        }
                    }
                }
            }
            .refreshable {
                await community.refreshFromServer()
            }
            .navigationTitle("EmPoster")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 14) {
                        NavigationLink {
                            LikesView()
                        } label: {
                            heartButton
                        }
                        Button {
                            selectedTab = profileTab
                        } label: {
                            profileAvatar
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack {
                        if community.isAdmin {
                            Menu {
                                if community.pending.isEmpty {
                                    Text("No pending submissions")
                                } else {
                                    Section("Pending Approval") {
                                        ForEach(community.pending) { submission in
                                            Button {
                                                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                                                community.approve(submission)
                                            } label: {
                                                Label(submission.title, systemImage: "checkmark.circle")
                                            }
                                            Button(role: .destructive) {
                                                UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                                                community.reject(submission)
                                            } label: {
                                                Label(submission.title, systemImage: "xmark.circle")
                                            }
                                        }
                                    }
                                }
                            } label: {
                                ZStack(alignment: .topTrailing) {
                                    Image(systemName: "shield.lefthalf.filled")
                                    if !community.pending.isEmpty {
                                        Text("\(community.pending.count)")
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundStyle(.white)
                                            .padding(3)
                                            .background(Circle().fill(Color.red))
                                            .offset(x: 10, y: -8)
                                    }
                                }
                            }
                        }
                        Menu {
                            if !pbManager.selectedTendies.isEmpty {
                                Section("Selected Tendies") {
                                    ForEach(pbManager.selectedTendies, id: \.self) { tendie in
                                        Text(tendie.deletingPathExtension().lastPathComponent)
                                    }
                                }
                            }
                            Button {
                                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                                showTendiesImporter.toggle()
                            } label: {
                                Label("Select Tendies", systemImage: "document.circle")
                            }
                            if !pbManager.selectedTendies.isEmpty || !pbManager.videos.isEmpty {
                                Button {
                                    applyTendies()
                                } label: {
                                    Label("Apply", systemImage: "checkmark.circle")
                                }
                            }
                            if !pbManager.selectedTendies.isEmpty {
                                Button(role: .destructive) {
                                    withAnimation {
                                        pbManager.selectedTendies.removeAll()
                                        pbManager.videos.removeAll()
                                    }
                                } label: {
                                    Label("Clear Selected", systemImage: "trash")
                                }
                            }
                            Button(role: .destructive) {
                                resetCollections()
                            } label: {
                                Label("Reset Collections", systemImage: "arrow.clockwise.circle")
                            }
                        } label: {
                            Image(systemName: "rectangle.stack")
                        }
                        NavigationLink(destination: {
                            SettingsView()
                        }, label: {
                            Image(systemName: "gear")
                        })
                    }
                }
            }
        }
        .fileImporter(isPresented: $showTendiesImporter, allowedContentTypes: [UTType(filenameExtension: "tendies", conformingTo: .data)!], allowsMultipleSelection: true, onCompletion: { result in
            switch result {
            case .success(let url):
                if pbManager.selectedTendies.count + url.count > PosterBoardManager.MaxTendies {
                    UIApplication.shared.alert(title: NSLocalizedString("Max Tendies Reached", comment: ""), body: String(format: NSLocalizedString("You can only apply %@ descriptors.", comment: ""), "\(PosterBoardManager.MaxTendies)"))
                } else {
                    pbManager.selectedTendies.append(contentsOf: url)
                }
            case .failure(let error):
                Haptic.shared.notify(.error)
                UIApplication.shared.alert(body: error.localizedDescription)
            }
        })
    }

    // MARK: - Feed

    private var emptyFeed: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No community wallpapers yet")
                .font(.headline)
            Text("Wallpapers submitted in Create appear here once staff approves them.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
        .padding(.horizontal, 32)
    }

    private var heartButton: some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: likes.count > 0 ? "heart.fill" : "heart")
                .font(.system(size: 18))
                .foregroundStyle(likes.count > 0 ? Color.red : Color.primary)
            if likes.count > 0 {
                Text("\(likes.count)")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(3)
                    .background(Circle().fill(Color.red))
                    .offset(x: 12, y: -8)
            }
        }
        .padding(4)
    }

    private var profileAvatar: some View {
        Circle()
            .fill(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: 30, height: 30)
            .overlay(
                Image(systemName: "person.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(.white)
            )
    }

    // MARK: - Add to Tendies

    private func addToTendies(_ submission: TendieSubmission) {
        guard pbManager.selectedTendies.count + submission.tendieFiles.count <= PosterBoardManager.MaxTendies else {
            Haptic.shared.notify(.error)
            UIApplication.shared.alert(
                title: NSLocalizedString("Max Tendies Reached", comment: ""),
                body: String(format: NSLocalizedString("You can only apply %@ descriptors.", comment: ""), "\(PosterBoardManager.MaxTendies)")
            )
            return
        }

        Task {
            do {
                for file in submission.tendieFiles {
                    let newURL: URL
                    if submission.isRemote, let url = ServerConfig.tendieURL(id: submission.id, fileName: file) {
                        newURL = try await DownloadManager.shared.downloadFromURL(url)
                    } else {
                        newURL = try DownloadManager.shared.copyTendies(from: community.localTendieURL(forStoredFile: file))
                    }
                    await MainActor.run {
                        pbManager.selectedTendies.append(newURL)
                    }
                }
                await MainActor.run {
                    Haptic.shared.notify(.success)
                    UIApplication.shared.alert(
                        title: "Added to Tendies",
                        body: "\"\(submission.title)\" was added to your collections. Apply it from the Tendies menu on the Home tab."
                    )
                }
            } catch {
                Haptic.shared.notify(.error)
                UIApplication.shared.alert(body: error.localizedDescription)
            }
        }
    }

    // MARK: - Tendie actions

    private func applyTendies() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        UIApplication.shared.alert(title: NSLocalizedString("Applying Wallpapers...", comment: ""), body: NSLocalizedString("Please wait", comment: ""), animated: false, withButton: false)

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                var hash = pbHash
                if hash.isEmpty {
                    UIApplication.shared.change(title: NSLocalizedString("Applying Wallpapers...", comment: ""), body: "Detecting PosterBoard container…")
                    hash = try BadQuery.findPosterBoardHash()
                    DispatchQueue.main.async { pbHash = hash }
                }
                try pbManager.applyTendies(appHash: hash)
                SymHandler.cleanup() // just to be extra sure
                try? FileManager.default.removeItem(at: pbManager.getTendiesStoreURL())

                DispatchQueue.main.async {
                    pbManager.selectedTendies.removeAll()
                    pbManager.videos.removeAll()
                    Haptic.shared.notify(.success)
                    // Instant Mond-style respring (no alert delay)
                    RespringHelper.respring()
                }
            } catch CocoaError.fileWriteUnknown {
                presentError(ApplyError.wrongAppHash)
            } catch CocoaError.fileWriteFileExists {
                presentError(ApplyError.collectionsNeedsReset)
            } catch {
                print(error.localizedDescription)
                presentError(ApplyError.unexpected(info: error.localizedDescription))
            }
        }
    }

    private func resetCollections() {
        UIApplication.shared.confirmAlert(
            title: NSLocalizedString("Reset Collections", comment: ""),
            body: SymHandler.prefersBadQuery
                ? "This will wipe custom PosterBoard descriptors via bad_query, then respring."
                : NSLocalizedString("Do you want to reset collections?", comment: ""),
            onOK: {
                UIApplication.shared.alert(
                    title: "Resetting…",
                    body: "Please wait",
                    animated: true,
                    withButton: false
                )
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        var hash = pbHash
                        if hash.isEmpty && SymHandler.prefersBadQuery {
                            hash = try BadQuery.findPosterBoardHash()
                            DispatchQueue.main.async { pbHash = hash }
                        }
                        guard !hash.isEmpty else {
                            throw ApplyError.wrongAppHash
                        }
                        try pbManager.resetCollections(appHash: hash)
                        DispatchQueue.main.async {
                            Haptic.shared.notify(.success)
                            // Instant Mond-style respring
                            RespringHelper.respring()
                        }
                    } catch {
                        presentError(ApplyError.unexpected(info: error.localizedDescription))
                    }
                }
            },
            noCancel: false
        )
    }

    private func presentError(_ error: ApplyError) {
        SymHandler.cleanup()
        DispatchQueue.main.async {
            Haptic.shared.notify(.error)
            // alert() dismisses any buttonless progress sheet first, always with OK
            UIApplication.shared.alert(body: error.localizedDescription, withButton: true)
        }
    }

    init(selectedTab: Binding<Int>) {
        self._selectedTab = selectedTab

        // Fix file picker
        let fixMethod = class_getInstanceMethod(UIDocumentPickerViewController.self, #selector(UIDocumentPickerViewController.fix_init(forOpeningContentTypes:asCopy:)))!
        let origMethod = class_getInstanceMethod(UIDocumentPickerViewController.self, #selector(UIDocumentPickerViewController.init(forOpeningContentTypes:asCopy:)))!
        method_exchangeImplementations(origMethod, fixMethod)
    }
}

// MARK: - Feed Post Card

private struct FeedPostCard: View {
    let submission: TendieSubmission
    let onAdd: () -> Void

    @ObservedObject private var likes = LikesManager.shared
    @ObservedObject private var comments = CommentsManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            NavigationLink {
                PostDetailView(submission: submission)
            } label: {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 10) {
                        avatar
                            .frame(width: 36, height: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(submission.authorName)
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                                    .lineLimit(1)
                                Spacer()
                                Text(timeAgo(submission.createdAt))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text("@\(submission.authorName)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    if !submission.title.isEmpty {
                        Text(submission.title)
                            .font(.headline)
                    }
                    if !submission.description.isEmpty {
                        Text(submission.description)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                    }

                    TendiePreviewImage(
                        previewURL: submission.isRemote ? ServerConfig.previewURL(id: submission.id) : nil,
                        storedFileName: submission.isRemote ? nil : submission.tendieFiles.first
                    )
                    .frame(height: 400)
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
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            HStack(spacing: 24) {
                NavigationLink {
                    PostDetailView(submission: submission)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "bubble.right")
                            .font(.system(size: 16))
                        if comments.comments(for: submission.id).count > 0 {
                            Text("\(comments.comments(for: submission.id).count)")
                        }
                    }
                }
                Button {
                    Haptic.shared.play(.light)
                    likes.toggle(submission.id)
                } label: {
                    Image(systemName: likes.isLiked(submission.id) ? "heart.fill" : "heart")
                        .font(.system(size: 18))
                        .foregroundStyle(likes.isLiked(submission.id) ? Color.red : Color.secondary)
                }
                Button(action: {
                    Haptic.shared.play(.light)
                    onAdd()
                }) {
                    Label("Add to Tendies", systemImage: "arrow.down.circle")
                }
                .font(.footnote)
                ShareLink(item: "Check out this tendie wallpaper: \(submission.title)") {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .font(.footnote)
                }
                Spacer()
            }
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var avatar: some View {
        Circle()
            .fill(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(
                Text(initials)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
            )
    }

    private var initials: String {
        let parts = submission.authorName
            .split(separator: " ")
            .prefix(2)
            .compactMap { $0.first.map(String.init) }
        return parts.isEmpty ? "?" : parts.joined()
    }
}

func timeAgo(_ date: Date) -> String {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .abbreviated
    return formatter.localizedString(for: date, relativeTo: Date())
}