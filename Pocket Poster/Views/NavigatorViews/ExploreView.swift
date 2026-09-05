//
//  ExploreView.swift
//  EmPoster
//
//  Created by lemin on 7/6/25.
//
//  Community tendie wallpaper library. Wallpapers shown here were
//  submitted in the Create tab and approved by staff — everyone can
//  browse and add them to their own collections.
//

import SwiftUI

let MIN_SIZE: CGFloat = 165
let CORNER_RADIUS: CGFloat = 12

struct ExploreView: View {
    @ObservedObject private var community = CommunityManager.shared

    @State var searchTerm: String = ""

    private var filtered: [TendieSubmission] {
        guard !searchTerm.isEmpty else { return community.approved }
        let query = searchTerm.lowercased()
        return community.approved.filter { submission in
            submission.title.lowercased().contains(query) ||
            submission.description.lowercased().contains(query) ||
            submission.tags.joined(separator: " ").lowercased().contains(query) ||
            submission.authorName.lowercased().contains(query)
        }
    }

    var body: some View {
        NavigationView {
            ScrollView {
                if filtered.isEmpty {
                    emptyState
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: MIN_SIZE))]) {
                        ForEach(filtered) { submission in
                            Button(action: {
                                Haptic.shared.play(.light)
                                addToTendies(submission)
                            }) {
                                submissionCard(submission)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                }
            }
            .searchable(text: $searchTerm)
            .navigationTitle("Explore")
        }
    }

    // MARK: - Card

    private func submissionCard(_ submission: TendieSubmission) -> some View {
        VStack(spacing: 0) {
            TendiePreviewImage(
                previewURL: submission.isRemote ? ServerConfig.previewURL(id: submission.id) : nil,
                storedFileName: submission.isRemote ? nil : submission.tendieFiles.first
            )
            .aspectRatio(9 / 16.0, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .cornerRadius(CORNER_RADIUS, corners: .topLeft)
            .cornerRadius(CORNER_RADIUS, corners: .topRight)
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(submission.title)
                        .foregroundStyle(Color(uiColor: .label))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                    Text(submission.authorName)
                        .foregroundColor(.secondary)
                        .font(.caption)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "arrow.down.circle")
                    .foregroundColor(.blue)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(height: 58)
        }
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(CORNER_RADIUS)
        .padding(4)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)

            Text(searchTerm.isEmpty ? "No Community Wallpapers Yet" : "No Results")
                .font(.title3)
                .fontWeight(.bold)

            Text(searchTerm.isEmpty
                 ? "Wallpapers submitted in the Create tab appear here once staff approves them."
                 : "Try a different search term.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Add to Tendies

    private func addToTendies(_ submission: TendieSubmission) {
        let pbManager = PosterBoardManager.shared

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
                        body: "\"\(submission.title)\" was added to your collections. Apply it from the Tendies tab."
                    )
                }
            } catch {
                Haptic.shared.notify(.error)
                UIApplication.shared.alert(body: error.localizedDescription)
            }
        }
    }
}

struct PullToRefresh: View {
    var coordinateSpaceName: String
    var onRefresh: ()->Void
    
    @State var needRefresh: Bool = false
    
    var body: some View {
        GeometryReader { geo in
            if (geo.frame(in: .named(coordinateSpaceName)).midY > 50) {
                Spacer()
                    .onAppear {
                        needRefresh = true
                    }
            } else if (geo.frame(in: .named(coordinateSpaceName)).maxY < 10) {
                Spacer()
                    .onAppear {
                        if needRefresh {
                            needRefresh = false
                            onRefresh()
                        }
                    }
            }
            HStack {
                Spacer()
                if needRefresh {
                    ProgressView()
                        .scaleEffect(1.75)
                        .onAppear {
                            Haptic.shared.play(.light)
                        }
                } else {
                    Text("")
                }
                Spacer()
            }
        }.padding(.top, -50)
    }
}