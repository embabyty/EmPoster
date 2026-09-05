//
//  ServerAPI.swift
//  EmPoster
//
//  Client for the Pocket Poster proxy server (see server/ in the repo).
//  The server handles Patreon OAuth (secret stays server-side) and the
//  community submissions / Explore feed.
//

import Foundation

// MARK: - Server config

enum ServerConfig {
    /// UserDefaults key storing the server base URL (set in Settings).
    static let baseURLKey = "serverBaseURL"

    /// Base URL of the Pocket Poster server, e.g. "http://192.168.1.50:3000".
    /// Defaults to localhost (Simulator); real devices set this in Settings.
    static var baseURL: String {
        let stored = UserDefaults.standard.string(forKey: baseURLKey) ?? ""
        let trimmed = stored.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "http://localhost:3000" : trimmed
    }

    /// URL that starts the server-side Patreon OAuth flow.
    static var loginURL: URL? {
        URL(string: baseURL + "/auth/patreon/login")
    }

    static func url(_ path: String) -> URL? {
        URL(string: baseURL + path)
    }

    /// Download URL for a tendie file hosted on the server.
    static func tendieURL(id: String, fileName: String) -> URL? {
        URL(string: baseURL + "/api/submissions/\(id)/tendie/\(fileName)")
    }

    /// Preview image URL for a submission hosted on the server.
    static func previewURL(id: String) -> URL? {
        URL(string: baseURL + "/api/submissions/\(id)/preview")
    }
}

// MARK: - Models

/// Identity returned by GET /api/me.
struct ServerMe: Codable {
    let email: String
    let name: String?
    let isOwner: Bool
    let isStaff: Bool
    let isAdmin: Bool
    let tier: String?
    let isUltra: Bool
}

/// Wire format of a submission returned by the server (ISO-8601 strings).
/// Mapped into `TendieSubmission` for the rest of the app.
struct ServerSubmissionDTO: Decodable {
    let id: String
    let title: String
    let description: String
    let tags: [String]
    let tendieFiles: [String]
    let previewFile: String?
    let authorName: String
    let status: String
    let createdAt: String
    let decidedAt: String?

    func asTendieSubmission() -> TendieSubmission {
        TendieSubmission(
            id: id,
            title: title,
            description: description,
            tags: tags,
            tendieFiles: tendieFiles,
            previewFile: previewFile,
            authorName: authorName,
            authorEmail: nil,
            status: TendieSubmission.Status(rawValue: status) ?? .pending,
            createdAt: Self.date(from: createdAt) ?? Date(),
            decidedAt: decidedAt.flatMap(Self.date(from:)),
            isRemote: true
        )
    }

    private static func date(from iso: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: iso) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: iso)
    }
}

// MARK: - API client

enum ServerAPIError: LocalizedError {
    case invalidURL
    case serverError(Int)
    case network(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The server URL is invalid."
        case .serverError(let code):
            return "Server returned an error (\(code)). Make sure the server is running and the Server URL in Settings is correct."
        case .network(let error):
            return "Could not reach the server: \(error.localizedDescription)"
        }
    }
}

enum ServerAPI {

    // MARK: - Auth

    /// Fetches the current identity for a session token.
    static func me(token: String) async throws -> ServerMe {
        guard let url = ServerConfig.url("/api/me") else { throw ServerAPIError.invalidURL }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await send(request)
        return try JSONDecoder().decode(ServerMe.self, from: data)
    }

    /// Invalidates a session on the server (best effort).
    static func logout(token: String) async {
        guard let url = ServerConfig.url("/api/logout") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        _ = try? await URLSession.shared.data(for: request)
    }

    // MARK: - Submissions

    /// Fetches the approved feed shown in Explore (public).
    static func fetchApproved() async throws -> [TendieSubmission] {
        try await fetchSubmissions(status: "approved")
    }

    /// Fetches the pending moderation queue (admin token required).
    static func fetchPending(token: String) async throws -> [TendieSubmission] {
        try await fetchSubmissions(status: "pending", token: token)
    }

    private static func fetchSubmissions(status: String, token: String? = nil) async throws -> [TendieSubmission] {
        guard let baseURL = ServerConfig.url("/api/submissions"),
              var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw ServerAPIError.invalidURL
        }
        components.queryItems = [URLQueryItem(name: "status", value: status)]
        guard let url = components.url else { throw ServerAPIError.invalidURL }

        var request = URLRequest(url: url)
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await send(request)
        return try JSONDecoder().decode([ServerSubmissionDTO].self, from: data).map { $0.asTendieSubmission() }
    }

    /// Uploads a submission with its tendie files and optional preview image.
    static func submit(
        token: String,
        title: String,
        description: String,
        tags: [String],
        authorName: String,
        localFiles: [String],
        preview: Data?
    ) async throws -> TendieSubmission {
        guard let url = ServerConfig.url("/api/submissions") else { throw ServerAPIError.invalidURL }

        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let tagsData = (try? JSONEncoder().encode(tags)) ?? Data("[]".utf8)

        var body = Data()
        func append(_ string: String) { body.append(Data(string.utf8)) }
        func addField(_ name: String, _ value: String) {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            append(value)
            append("\r\n")
        }
        func addFile(_ name: String, fileName: String, mime: String, data: Data) {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(fileName)\"\r\n")
            append("Content-Type: \(mime)\r\n\r\n")
            body.append(data)
            append("\r\n")
        }

        addField("title", title)
        addField("description", description)
        addField("tags", String(data: tagsData, encoding: .utf8) ?? "[]")
        addField("authorName", authorName)

        for name in localFiles {
            let fileURL = communityStoreDirectory().appendingPathComponent(name)
            guard let data = try? Data(contentsOf: fileURL) else { continue }
            addFile("tendies", fileName: name, mime: "application/octet-stream", data: data)
        }
        if let preview {
            addFile("preview", fileName: "preview.jpg", mime: "image/jpeg", data: preview)
        }
        append("--\(boundary)--\r\n")

        let (data, response) = try await send(request, with: body)
        return try JSONDecoder().decode(ServerSubmissionDTO.self, from: data).asTendieSubmission()
    }

    /// Approves or rejects a pending submission (admin token required).
    static func setStatus(id: String, token: String, approve: Bool) async throws -> TendieSubmission {
        let action = approve ? "approve" : "reject"
        guard let url = ServerConfig.url("/api/submissions/\(id)/\(action)") else { throw ServerAPIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await send(request)
        return try JSONDecoder().decode(ServerSubmissionDTO.self, from: data).asTendieSubmission()
    }

    // MARK: - Helpers

    private static func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            try validate(response)
            return (data, response)
        } catch let error as ServerAPIError {
            throw error
        } catch {
            throw ServerAPIError.network(error)
        }
    }

    private static func send(_ request: URLRequest, with body: Data) async throws -> (Data, URLResponse) {
        do {
            let (data, response) = try await URLSession.shared.upload(for: request, from: body)
            try validate(response)
            return (data, response)
        } catch let error as ServerAPIError {
            throw error
        } catch {
            throw ServerAPIError.network(error)
        }
    }

    private static func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200...299).contains(http.statusCode) else {
            throw ServerAPIError.serverError(http.statusCode)
        }
    }
}