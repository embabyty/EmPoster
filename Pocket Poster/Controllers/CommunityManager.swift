//
//  CommunityManager.swift
//  EmPoster
//
//  Created by lemin on 9/5/25.
//
//  Community tendie wallpaper library.
//  Users submit tendies in the Create tab; they only appear in Explore
//  after an admin/staff member approves them.
//
//  Backend: the Pocket Poster proxy server (see server/ in the repo).
//  Submissions and files are uploaded to the server when a session exists;
//  if the server is unreachable, everything falls back to local storage so
//  the app keeps working on-device.
//

import Foundation
import UIKit
import ZIPFoundation

// MARK: - Model

struct TendieSubmission: Identifiable, Codable {
    var id: String = UUID().uuidString
    var title: String
    var description: String
    var tags: [String]
    /// Local file names (inside the community store directory) when the
    /// submission is local-only, or server file names when it is remote.
    var tendieFiles: [String]
    /// File name of the preview image on the server (remote submissions only).
    var previewFile: String?
    /// Patreon account that submitted the wallpaper (or "Anonymous").
    var authorName: String
    var authorEmail: String?
    var status: Status = .pending
    var createdAt: Date = Date()
    var decidedAt: Date?
    /// True when this submission lives on the proxy server.
    var isRemote: Bool = false

    enum Status: String, Codable {
        case pending
        case approved
        case rejected
    }
}

// MARK: - Config / Admins

enum CommunityConfig {
    /// Patreon accounts allowed to log in and approve/reject submissions.
    /// The app owner is always allowed; add staff/admin patron emails here.
    static let adminEmails: [String] = [PatreonConfig.ownerEmail] + PatreonConfig.staffEmails
}

// MARK: - Storage Location

/// Directory where local tendie files and submissions cache live.
/// Standalone so preview extraction can use it off the main actor.
func communityStoreDirectory() -> URL {
    let fm = FileManager.default
    let dir = SymHandler.getDocumentsDirectory().appendingPathComponent("Community Submissions", conformingTo: .directory)
    if !fm.fileExists(atPath: dir.path()) {
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    return dir
}

// MARK: - Manager

@MainActor
final class CommunityManager: ObservableObject {
    static let shared = CommunityManager()

    @Published private(set) var submissions: [TendieSubmission] = []

    /// Approved submissions, newest first. These are shown in Explore.
    var approved: [TendieSubmission] {
        submissions
            .filter { $0.status == .approved }
            .sorted { $0.createdAt > $1.createdAt }
    }

    /// Pending submissions, newest first. Admin-only moderation queue.
    var pending: [TendieSubmission] {
        submissions
            .filter { $0.status == .pending }
            .sorted { $0.createdAt > $1.createdAt }
    }

    /// Whether the logged-in account may approve/reject requests.
    /// Prefers the server's verdict; falls back to the local email list.
    var isAdmin: Bool {
        if PatreonManager.shared.isAdmin { return true }
        guard let email = PatreonManager.shared.memberEmail?.lowercased() else { return false }
        return CommunityConfig.adminEmails.contains(email)
    }

    private var cacheURL: URL {
        communityStoreDirectory().appendingPathComponent("submissions.json")
    }

    private init() {
        loadCache()
        Task { await refreshFromServer() }
    }

    // MARK: - Cache

    func loadCache() {
        guard let data = try? Data(contentsOf: cacheURL),
              let decoded = try? JSONDecoder().decode([TendieSubmission].self, from: data) else { return }
        submissions = decoded
    }

    private func saveCache() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(submissions) {
            try? data.write(to: cacheURL, options: .atomic)
        }
    }

    // MARK: - Server sync

    /// Pulls the approved feed (and the pending queue for admins) from the
    /// server and merges it with any local-only submissions.
    func refreshFromServer() async {
        if let token = PatreonManager.shared.sessionToken, PatreonManager.shared.isAdmin {
            do {
                async let approved = ServerAPI.fetchApproved()
                async let pending = ServerAPI.fetchPending(token: token)
                let (a, p) = try await (approved, pending)
                mergeRemote(a + p)
                saveCache()
            } catch {
                print("Community server refresh failed: \(error.localizedDescription)")
            }
        } else {
            do {
                let approved = try await ServerAPI.fetchApproved()
                mergeRemote(approved)
                saveCache()
            } catch {
                print("Community server refresh failed: \(error.localizedDescription)")
            }
        }
    }

    /// Replaces remote submissions with freshly fetched ones, keeping any
    /// local-only submissions (created while the server was unreachable).
    private func mergeRemote(_ remote: [TendieSubmission]) {
        submissions.removeAll { $0.isRemote }
        submissions.append(contentsOf: remote)
    }

    // MARK: - Tendie storage

    /// Copies an imported tendie file into the community submissions folder
    /// and returns its stored file name.
    func storeTendie(from url: URL) throws -> String {
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped { url.stopAccessingSecurityScopedResource() }
        }
        let name = UUID().uuidString + (url.pathExtension.isEmpty ? "" : ".\(url.pathExtension)")
        let dest = communityStoreDirectory().appendingPathComponent(name)
        try FileManager.default.copyItem(at: url, to: dest)
        return name
    }

    /// Resolves a stored file name to its local URL.
    func localTendieURL(forStoredFile name: String) -> URL {
        communityStoreDirectory().appendingPathComponent(name)
    }

    // MARK: - Submission actions

    /// Submits a wallpaper request. Uploads it to the server when a session
    /// exists; otherwise stores it locally. Either way the status starts as
    /// pending and nothing is published until an admin approves it.
    func submit(title: String, description: String, tags: [String], tendieFiles: [String]) async {
        let patreon = PatreonManager.shared
        let authorName = patreon.memberName ?? "Anonymous"
        let authorEmail = patreon.memberEmail

        if let token = patreon.sessionToken {
            do {
                // Best-effort preview thumbnail built from the first tendie.
                var preview: Data?
                if let first = tendieFiles.first {
                    let image = await Task.detached(priority: .utility) {
                        CommunityPreviewStore.image(forStoredFile: first)
                    }.value
                    preview = image.flatMap { CommunityPreviewStore.thumbnailJPEG(from: $0) }
                }

                let remote = try await ServerAPI.submit(
                    token: token,
                    title: title,
                    description: description,
                    tags: tags,
                    authorName: authorName,
                    localFiles: tendieFiles,
                    preview: preview
                )
                submissions.insert(remote, at: 0)
                saveCache()
                return
            } catch {
                // Fall through to local-only submission so the user never loses their work.
                print("Server submit failed, keeping local: \(error.localizedDescription)")
            }
        }

        // Local-only fallback
        let submission = TendieSubmission(
            title: title,
            description: description,
            tags: tags,
            tendieFiles: tendieFiles,
            authorName: authorName,
            authorEmail: authorEmail
        )
        submissions.insert(submission, at: 0)
        saveCache()
    }

    /// Approves a pending submission (admin only). Syncs to the server.
    func approve(_ submission: TendieSubmission) {
        setStatus(submission, to: .approved)
    }

    /// Rejects a pending submission (admin only). Syncs to the server.
    func reject(_ submission: TendieSubmission) {
        setStatus(submission, to: .rejected)
    }

    private func setStatus(_ submission: TendieSubmission, to status: TendieSubmission.Status) {
        guard isAdmin else { return }

        // Local mirror first
        mutate(submission.id) { $0.status = status; $0.decidedAt = Date() }

        // Sync to the server if it came from there
        guard submission.isRemote, let token = PatreonManager.shared.sessionToken else { return }
        Task {
            do {
                let updated = try await ServerAPI.setStatus(id: submission.id, token: token, approve: status == .approved)
                mutate(updated.id) { $0.status = updated.status; $0.decidedAt = updated.decidedAt }
            } catch {
                print("Failed to sync status: \(error.localizedDescription)")
            }
        }
    }

    private func mutate(_ id: String, _ change: (inout TendieSubmission) -> Void) {
        guard let idx = submissions.firstIndex(where: { $0.id == id }) else { return }
        change(&submissions[idx])
        saveCache()
    }
}

// MARK: - Preview extraction

/// Extracts a wallpaper preview image out of a stored tendie file
/// (which is a zip of PosterBoard descriptors). Best-effort: finds the
/// largest image inside and caches it in memory.
enum CommunityPreviewStore {
    private static var cache: [String: UIImage] = [:]

    static func image(forStoredFile name: String) -> UIImage? {
        if let cached = cache[name] { return cached }

        let fileURL = communityStoreDirectory().appendingPathComponent(name)
        let fm = FileManager.default
        guard fm.fileExists(atPath: fileURL.path()) else { return nil }

        let tempDir = SymHandler.getDocumentsDirectory().appendingPathComponent("PreviewExtract", conformingTo: .directory)
        defer { try? fm.removeItem(at: tempDir) }
        try? fm.createDirectory(at: tempDir, withIntermediateDirectories: true)

        do {
            try fm.unzipItem(at: fileURL, to: tempDir)
        } catch {
            return nil
        }

        let imageExts: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "gif"]
        var best: UIImage?
        var bestSize: Int = -1
        if let enumerator = fm.enumerator(
            at: tempDir,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) {
            for case let fileURL as URL in enumerator {
                guard imageExts.contains(fileURL.pathExtension.lowercased()) else { continue }
                guard let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize,
                      size > bestSize else { continue }
                if let img = UIImage(contentsOfFile: fileURL.path) {
                    best = img
                    bestSize = size
                }
            }
        }

        if let best { cache[name] = best }
        return best
    }

    /// Downscales an image to a small JPEG for the server preview upload.
    static func thumbnailJPEG(from image: UIImage, maxDimension: CGFloat = 512) -> Data? {
        let longest = max(image.size.width, image.size.height)
        guard longest > 0 else { return nil }
        let scale = min(1, maxDimension / longest)
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
        return resized.jpegData(compressionQuality: 0.75)
    }
}