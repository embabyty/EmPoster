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
//  Backend: Firebase (Firestore + Storage) when configured. Without a
//  GoogleService-Info.plist everything falls back to local storage so
//  the app keeps working.
//

import Foundation
import UIKit
import ZIPFoundation
import FirebaseFirestore
import FirebaseStorage

// MARK: - Model

struct TendieSubmission: Identifiable, Codable {
    var id: String = UUID().uuidString
    var title: String
    var description: String
    var tags: [String]
    /// Either local file names (offline mode) or Firebase Storage paths
    /// (Firebase mode) of the tendie wallpaper files.
    var tendieFiles: [String]
    /// Firebase Storage path of the preview thumbnail (Firebase mode only).
    var previewPath: String?
    /// Patreon account that submitted the wallpaper (or "Anonymous").
    var authorName: String
    var authorEmail: String?
    var status: Status = .pending
    var createdAt: Date = Date()
    var decidedAt: Date?

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
    @Published private(set) var syncError: String?

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

    /// Whether the logged-in Patreon account may approve/reject requests.
    var isAdmin: Bool {
        guard let email = PatreonManager.shared.memberEmail?.lowercased() else { return false }
        return CommunityConfig.adminEmails.contains(email)
    }

    var firebaseAvailable: Bool {
        FirebaseManager.shared.isConfigured
    }

    private var listener: ListenerRegistration?
    private var cacheURL: URL {
        communityStoreDirectory().appendingPathComponent("submissions.json")
    }

    private init() {
        loadCache()
        Task {
            await FirebaseManager.shared.ensureSignedIn()
            if FirebaseManager.shared.isConfigured {
                attachListener()
            }
        }
    }

    // MARK: - Cache (offline fallback + instant UI)

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

    // MARK: - Firestore sync

    private func attachListener() {
        let ref = FirebaseManager.shared.db.collection("submissions")
        listener = ref.addSnapshotListener { [weak self] snapshot, error in
            guard let self else { return }
            if let error {
                self.syncError = error.localizedDescription
                return
            }
            self.syncError = nil
            guard let docs = snapshot?.documents else { return }

            self.submissions = docs.compactMap { doc in
                Self.decode(from: doc.data(), id: doc.documentID)
            }
            self.saveCache()
        }
    }

    /// Converts a Firestore document into a submission model.
    private static func decode(from data: [String: Any], id: String) -> TendieSubmission? {
        guard let title = data["title"] as? String,
              let statusRaw = data["status"] as? String,
              let status = TendieSubmission.Status(rawValue: statusRaw) else { return nil }

        let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
        let decidedAt = (data["decidedAt"] as? Timestamp)?.dateValue()

        return TendieSubmission(
            id: id,
            title: title,
            description: data["description"] as? String ?? "",
            tags: data["tags"] as? [String] ?? [],
            tendieFiles: data["tendieFiles"] as? [String] ?? [],
            previewPath: data["previewPath"] as? String,
            authorName: data["authorName"] as? String ?? "Anonymous",
            authorEmail: data["authorEmail"] as? String,
            status: status,
            createdAt: createdAt,
            decidedAt: decidedAt
        )
    }

    // MARK: - Tendie storage (offline mode)

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

    /// Resolves a stored file name (offline mode) to its local URL.
    func localTendieURL(forStoredFile name: String) -> URL {
        communityStoreDirectory().appendingPathComponent(name)
    }

    // MARK: - Submission actions

    /// Submits a wallpaper request. Uploads to Firebase when configured,
    /// otherwise stores locally. Either way the status starts as pending
    /// and nothing is published until an admin approves it.
    func submit(title: String, description: String, tags: [String], tendieFiles: [String]) async {
        let patreon = PatreonManager.shared
        let firebase = FirebaseManager.shared

        // Prefer the Patreon account; fall back to the Google account.
        let authorName = patreon.memberName ?? firebase.currentUserName ?? "Anonymous"
        let authorEmail = patreon.memberEmail ?? firebase.currentUserEmail

        if FirebaseManager.shared.isConfigured {
            do {
                try await uploadAndSubmit(
                    title: title,
                    description: description,
                    tags: tags,
                    localFiles: tendieFiles,
                    authorName: authorName,
                    authorEmail: authorEmail
                )
                return
            } catch {
                syncError = error.localizedDescription
                // fall through to local-only submission so the user never loses their work
            }
        }

        // Local-only fallback
        let submission = TendieSubmission(
            title: title,
            description: description,
            tags: tags,
            tendieFiles: tendieFiles,
            previewPath: nil,
            authorName: authorName,
            authorEmail: authorEmail
        )
        submissions.insert(submission, at: 0)
        saveCache()
    }

    private func uploadAndSubmit(title: String, description: String, tags: [String], localFiles: [String], authorName: String, authorEmail: String?) async throws {
        let fb = FirebaseManager.shared
        let docRef = fb.db.collection("submissions").document()
        let docID = docRef.documentID

        // 1. Upload the tendie files
        var storagePaths: [String] = []
        for localName in localFiles {
            let path = "submissions/\(docID)/\(UUID().uuidString).tendies"
            let localURL = localTendieURL(forStoredFile: localName)
            try await fb.uploadFile(from: localURL, to: path)
            storagePaths.append(path)
        }

        // 2. Upload a preview thumbnail (best-effort)
        var previewPath: String?
        if let first = localFiles.first,
           let image = await Task.detached(priority: .utility, operation: {
               CommunityPreviewStore.image(forStoredFile: first)
           }).value,
           let jpeg = CommunityPreviewStore.thumbnailJPEG(from: image) {
            let path = "submissions/\(docID)/preview.jpg"
            try? await fb.uploadData(jpeg, to: path)
            previewPath = path
        }

        // 3. Create the Firestore document (pending)
        var data: [String: Any] = [
            "title": title,
            "description": description,
            "tags": tags,
            "tendieFiles": storagePaths,
            "authorName": authorName,
            "status": TendieSubmission.Status.pending.rawValue,
            "createdAt": FieldValue.serverTimestamp()
        ]
        if let authorEmail { data["authorEmail"] = authorEmail }
        if let previewPath { data["previewPath"] = previewPath }
        try await docRef.setData(data)

        // 4. Mirror locally so the queue/UI updates instantly
        let mirror = TendieSubmission(
            id: docID,
            title: title,
            description: description,
            tags: tags,
            tendieFiles: storagePaths,
            previewPath: previewPath,
            authorName: authorName,
            authorEmail: authorEmail,
            status: .pending,
            createdAt: Date()
        )
        submissions.insert(mirror, at: 0)
        saveCache()
    }

    /// Approves a pending submission (admin only). Syncs to Firestore.
    func approve(_ submission: TendieSubmission) {
        updateStatus(submission, to: .approved)
    }

    /// Rejects a pending submission (admin only). Syncs to Firestore.
    func reject(_ submission: TendieSubmission) {
        updateStatus(submission, to: .rejected)
    }

    private func updateStatus(_ submission: TendieSubmission, to status: TendieSubmission.Status) {
        guard isAdmin else { return }

        // Local mirror first
        mutate(submission.id) { $0.status = status; $0.decidedAt = Date() }

        // Sync to Firestore
        if FirebaseManager.shared.isConfigured {
            let db = FirebaseManager.shared.db
            db.collection("submissions").document(submission.id).updateData([
                "status": status.rawValue,
                "decidedAt": FieldValue.serverTimestamp()
            ]) { [weak self] error in
                if let error {
                    self?.syncError = error.localizedDescription
                }
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
        var bestSize: Int64 = -1
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

    /// Downscales an image to a small JPEG for upload (Storage previews).
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