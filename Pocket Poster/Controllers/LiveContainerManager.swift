//
//  LiveContainerManager.swift
//  EmPoster
//
//  LiveContainer-style Pro feature: apps are "installed" into EmPoster's own
//  sandbox (a container) instead of onto the iDevice. Imported bundles live
//  under Documents/LiveContainer and are never registered with the system.
//  Running is handled by handing the IPA to LiveContainer (or any sideloader)
//  via the share sheet, or by opening LiveContainer directly. bad_query is
//  used for on-device container access, e.g. cloning data from an app that is
//  actually installed on the device.
//

import Foundation
import UIKit
import ZIPFoundation

enum LiveContainerError: LocalizedError {
    case invalidBundle
    case missingInfoPlist(String)
    case unreadableInfoPlist(String, String)
    case missingBundleID(String)
    case noAppInArchive(String)
    case badQueryUnavailable
    case exportFailed
    case installFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidBundle:
            return "That doesn't look like an app package. Share an .ipa or .app with an app bundle inside."
        case .missingInfoPlist(let path):
            return "Found an app bundle at \(path), but it has no Info.plist file. Make sure you selected an .ipa or .app that contains a real app."
        case .unreadableInfoPlist(let path, let reason):
            return "The app bundle at \(path) has an Info.plist that couldn't be read (\(reason)). The IPA may be corrupted or protected."
        case .missingBundleID(let path):
            return "The app bundle at \(path) has an Info.plist, but it doesn't contain a CFBundleIdentifier, so it can't be installed."
        case .noAppInArchive(let path):
            return "The archive at \(path) doesn't contain an app bundle (no Info.plist found inside). It may not be a real IPA, or it may be corrupted."
        case .badQueryUnavailable:
            return "bad_query is not available on this iOS version."
        case .exportFailed:
            return "Could not re-archive the app as an IPA."
        case .installFailed(let info):
            return info
        }
    }
}

/// An app installed into EmPoster's container (not on the iDevice).
struct InstalledApp: Identifiable, Hashable {
    var id: String { bundleID }

    let bundleID: String
    let name: String
    let version: String
    let minOSVersion: String?
    /// The extracted .app bundle inside EmPoster's sandbox.
    let appBundleURL: URL
    /// Per-app data container (Documents/Library live here, LiveContainer-style).
    let dataContainerURL: URL
    let importedAt: Date
    /// Combined size of the app bundle + data container.
    let size: Int64
}

final class LiveContainerManager: ObservableObject {
    static let shared = LiveContainerManager()

    @Published private(set) var apps: [InstalledApp] = []

    private var iconCache: [String: UIImage] = [:]

    private init() {
        refresh()
    }

    // MARK: - Storage layout

    static let storageFolderName = "LiveContainer"

    var rootURL: URL {
        SymHandler.getDocumentsDirectory()
            .appendingPathComponent(LiveContainerManager.storageFolderName, conformingTo: .directory)
    }

    var applicationsURL: URL {
        rootURL.appendingPathComponent("Applications", conformingTo: .directory)
    }

    var dataURL: URL {
        rootURL.appendingPathComponent("Data", conformingTo: .directory)
    }

    var importsURL: URL {
        rootURL.appendingPathComponent("Imports", conformingTo: .directory)
    }

    var exportsURL: URL {
        rootURL.appendingPathComponent("Exports", conformingTo: .directory)
    }

    var metadataURL: URL {
        rootURL.appendingPathComponent("Apps.plist")
    }

    // MARK: - LiveContainer detection

    /// True when a LiveContainer instance is installed on the device.
    var isLiveContainerInstalled: Bool {
        UIApplication.shared.canOpenURL(URL(string: "livecontainer://")!)
            || UIApplication.shared.canOpenURL(URL(string: "livecontainer2://")!)
            || UIApplication.shared.canOpenURL(URL(string: "livecontainer3://")!)
    }

    func openLiveContainer() {
        let scheme = isLiveContainerInstalled ? "livecontainer://" : "https://livecontainer.github.io/"
        if let url = URL(string: scheme) {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
    }

    // MARK: - Async API (file work off the main actor, refresh on main)

    func install(from url: URL) async throws {
        try await Task.detached(priority: .userInitiated) {
            try self.performInstall(from: url)
        }.value
        refresh()
    }

    func uninstall(_ app: InstalledApp) async throws {
        try await Task.detached(priority: .userInitiated) {
            try self.performUninstall(app)
        }.value
        refresh()
    }

    func resetData(_ app: InstalledApp) async throws {
        try await Task.detached(priority: .userInitiated) {
            try self.performResetData(app)
        }.value
        refresh()
    }

    func exportIPA(for app: InstalledApp) async throws -> URL {
        try await Task.detached(priority: .userInitiated) {
            try self.performExportIPA(app)
        }.value
    }

    /// Clone Documents + preferences from the on-device installation of the
    /// same bundle ID into this app's data container (bad_query).
    func importDataFromInstalledApp(_ app: InstalledApp) async throws -> Int {
        try await Task.detached(priority: .userInitiated) {
            try self.performImportData(app)
        }.value
    }

    // MARK: - Public helpers

    func icon(for app: InstalledApp) -> UIImage? {
        if let cached = iconCache[app.bundleID] { return cached }
        let image = Self.loadIcon(from: app.appBundleURL, info: Self.readInfoPlist(app.appBundleURL))
        iconCache[app.bundleID] = image
        return image
    }

    func refresh() {
        let meta = loadMetadata()
        let fm = FileManager.default
        var result: [InstalledApp] = []

        guard let appDirs = try? fm.contentsOfDirectory(
            at: applicationsURL,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ) else {
            apps = []
            return
        }

        for dir in appDirs where dir.pathExtension == "app" {
            let bundleID = dir.deletingPathExtension().lastPathComponent
            let infoPlist = Self.readInfoPlist(dir)
            guard infoPlist["CFBundleIdentifier"] != nil else { continue }

            let entry = meta[bundleID] as? [String: Any]
            let name = (entry?["name"] as? String)
                ?? (infoPlist["CFBundleDisplayName"] as? String)
                ?? (infoPlist["CFBundleName"] as? String)
                ?? bundleID
            let version = (entry?["version"] as? String)
                ?? (infoPlist["CFBundleShortVersionString"] as? String)
                ?? (infoPlist["CFBundleVersion"] as? String)
                ?? ""
            let minOS = (entry?["minOSVersion"] as? String) ?? (infoPlist["MinimumOSVersion"] as? String)
            let containerName = (entry?["dataContainer"] as? String) ?? UUID().uuidString
            let dataContainer = dataURL
                .appendingPathComponent(bundleID, conformingTo: .directory)
                .appendingPathComponent(containerName, conformingTo: .directory)
            let importedAt = Date(timeIntervalSince1970: (entry?["importedAt"] as? Double) ?? 0)
            let size = Self.directorySize(at: dir) + Self.directorySize(at: dataContainer)

            result.append(InstalledApp(
                bundleID: bundleID,
                name: name,
                version: version,
                minOSVersion: minOS,
                appBundleURL: dir,
                dataContainerURL: dataContainer,
                importedAt: importedAt,
                size: size
            ))
        }

        result.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        apps = result
    }

    /// Installs an .ipa / .app received via "Open in EmPoster" (Files app).
    func handleIncomingIPA(_ url: URL) {
        UIApplication.shared.alert(
            title: "Installing app…",
            body: url.lastPathComponent,
            animated: false,
            withButton: false
        )
        Task {
            do {
                try await install(from: url)
                Haptic.shared.notify(.success)
                UIApplication.shared.dismissAlert(animated: true)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    UIApplication.shared.alert(
                        title: "App installed into EmPoster",
                        body: "Stored in EmPoster's container — nothing was installed on your device. Open the Apps tab and tap Run to launch it via LiveContainer."
                    )
                }
            } catch {
                Haptic.shared.notify(.error)
                UIApplication.shared.dismissAlert(animated: true)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    UIApplication.shared.alert(title: "Install failed", body: error.localizedDescription)
                }
            }
        }
    }

    // MARK: - Sync implementation

    private func performInstall(from url: URL) throws {
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing { url.stopAccessingSecurityScopedResource() }
        }

        let fm = FileManager.default
        try ensureDirectories()

        // Resolve the actual .app bundle from an .ipa archive or a raw .app folder.
        let sourceBundle: URL
        if url.pathExtension.lowercased() == "ipa" || url.pathExtension.lowercased() == "tipa" {
            let tmp = importsURL.appendingPathComponent(UUID().uuidString, conformingTo: .directory)
            try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: tmp) }

            // 1) Normal bulk extraction.
            var unzipError: Error?
            do {
                try fm.unzipItem(at: url, to: tmp)
            } catch {
                unzipError = error
                print("LiveContainer: bulk unzip failed (\(error.localizedDescription)); falling back to per-entry extraction")
            }

            // 2) If the bulk extraction produced no usable bundle, open the
            //    archive and pull just the .app folder out, entry by entry,
            //    skipping anything weird instead of aborting.
            if let archive = try? Archive(url: url, accessMode: .read) {
                if Self.findAppBundle(in: tmp) == nil,
                   let folder = Self.appFolderPath(in: archive) {
                    let appName = (folder as NSString).lastPathComponent
                    let dest = tmp.appendingPathComponent(appName, conformingTo: .directory)
                    if (try? Self.extractFolder(fromArchive: archive, folderPath: folder, to: dest)) == true {
                        print("LiveContainer: extracted app folder \(folder) entry-by-entry")
                    }
                }
            }

            guard let app = Self.findAppBundle(in: tmp) else {
                Self.logLayout(at: tmp, label: "Unzipped IPA contents")
                // The zip genuinely has no app bundle inside: say so.
                if let archive = try? Archive(url: url, accessMode: .read) {
                    if Self.appFolderPath(in: archive) == nil {
                        if let unzipError {
                            throw LiveContainerError.installFailed("Could not unzip the IPA: \(unzipError.localizedDescription)")
                        }
                        throw LiveContainerError.noAppInArchive(url.path)
                    }
                }
                // A zip with an app inside, but we couldn't materialize it on
                // disk. Surface the extraction failure if there was one.
                if let unzipError {
                    throw LiveContainerError.installFailed("Could not unzip the IPA: \(unzipError.localizedDescription)")
                }
                throw LiveContainerError.invalidBundle
            }
            sourceBundle = app
        } else {
            // Raw .app folder (or a folder containing one) picked from Files.
            guard let app = Self.findAppBundle(in: url) else {
                Self.logLayout(at: url, label: "Picked app folder contents")
                throw LiveContainerError.invalidBundle
            }
            sourceBundle = app
        }

        print("LiveContainer: resolved app bundle at \(sourceBundle.path)")
        var info: [String: Any]
        do {
            info = try Self.readInfoPlistThrowing(sourceBundle)
        } catch {
            // The extracted copy may be broken (e.g. conflicts during
            // extraction). Read the plist straight out of the zip.
            if url.pathExtension.lowercased() == "ipa" || url.pathExtension.lowercased() == "tipa" {
                if let fromArchive = try? Self.readInfoPlistFromArchive(try? Archive(url: url, accessMode: .read)) {
                    info = fromArchive.plist
                    print("LiveContainer: Info.plist read from the archive directly (on-disk copy was unreadable: \(error.localizedDescription))")
                    // Patch the broken on-disk copy with the good bytes.
                    if let archive = try? Archive(url: url, accessMode: .read),
                       let entry = archive.first(where: {
                           Self.normalizedEntryPath($0.path) == Self.normalizedEntryPath(fromArchive.folder) + "info.plist"
                       }) {
                        let dest = sourceBundle.appendingPathComponent("Info.plist")
                        try? fm.removeItem(at: dest)
                        _ = try? archive.extract(entry, to: dest)
                    }
                } else {
                    throw error
                }
            } else {
                throw error
            }
        }
        guard let bundleID = info["CFBundleIdentifier"] as? String, !bundleID.isEmpty else {
            throw LiveContainerError.missingBundleID(sourceBundle.path)
        }
        let name = (info["CFBundleDisplayName"] as? String)
            ?? (info["CFBundleName"] as? String)
            ?? sourceBundle.deletingPathExtension().lastPathComponent
        let version = (info["CFBundleShortVersionString"] as? String)
            ?? (info["CFBundleVersion"] as? String)
            ?? "1.0"
        let minOS = info["MinimumOSVersion"] as? String

        // Move the bundle into the container (replace an existing install).
        let target = applicationsURL.appendingPathComponent("\(bundleID).app", conformingTo: .directory)
        if fm.fileExists(atPath: target.path) {
            try fm.removeItem(at: target)
        }
        try fm.copyItem(at: sourceBundle, to: target)

        // Reuse the existing data container if present, else create a new one.
        var meta = loadMetadata()
        let previous = meta[bundleID] as? [String: Any]
        let containerName = (previous?["dataContainer"] as? String) ?? UUID().uuidString
        let dataContainer = dataURL
            .appendingPathComponent(bundleID, conformingTo: .directory)
            .appendingPathComponent(containerName, conformingTo: .directory)
        try fm.createDirectory(at: dataContainer, withIntermediateDirectories: true)

        meta[bundleID] = [
            "bundleID": bundleID,
            "name": name,
            "version": version,
            "minOSVersion": minOS ?? "",
            "dataContainer": containerName,
            "importedAt": Date().timeIntervalSince1970
        ]
        try writeMetadata(meta)
    }

    private func performUninstall(_ app: InstalledApp) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: app.appBundleURL.path) {
            try fm.removeItem(at: app.appBundleURL)
        }
        let dataRoot = dataURL.appendingPathComponent(app.bundleID, conformingTo: .directory)
        if fm.fileExists(atPath: dataRoot.path) {
            try fm.removeItem(at: dataRoot)
        }
        var meta = loadMetadata()
        meta.removeValue(forKey: app.bundleID)
        try writeMetadata(meta)
    }

    private func performResetData(_ app: InstalledApp) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: app.dataContainerURL.path) {
            try fm.removeItem(at: app.dataContainerURL)
        }
        try fm.createDirectory(at: app.dataContainerURL, withIntermediateDirectories: true)
    }

    private func performExportIPA(_ app: InstalledApp) throws -> URL {
        let fm = FileManager.default
        try ensureDirectories()

        // Build a proper Payload/<Name>.app IPA so any installer accepts it.
        let staging = exportsURL.appendingPathComponent(UUID().uuidString, conformingTo: .directory)
        defer { try? fm.removeItem(at: staging) }
        let payload = staging.appendingPathComponent("Payload", conformingTo: .directory)
        try fm.createDirectory(at: payload, withIntermediateDirectories: true)
        try fm.copyItem(
            at: app.appBundleURL,
            to: payload.appendingPathComponent(app.appBundleURL.lastPathComponent, conformingTo: .directory)
        )

        let fileName = "\(Self.sanitize(app.name))-\(Self.sanitize(app.version)).ipa"
        let out = exportsURL.appendingPathComponent(fileName)
        if fm.fileExists(atPath: out.path) {
            try fm.removeItem(at: out)
        }
        do {
            try fm.zipItem(at: payload, to: out, shouldKeepParent: false)
        } catch {
            throw LiveContainerError.exportFailed
        }
        return out
    }

    private func performImportData(_ app: InstalledApp) throws -> Int {
        guard BadQuery.isAvailable else { throw LiveContainerError.badQueryUnavailable }

        let hash = try BadQuery.findAppHash(bundleId: app.bundleID)
        let containerRoot = BadQuery.applicationContainerPath(appHash: hash)
        let fm = FileManager.default
        try fm.createDirectory(at: app.dataContainerURL, withIntermediateDirectories: true)

        var handles: [BadQueryHandle] = []
        defer { handles.forEach { $0.release() } }

        let sources: [(String, URL)] = [
            ((containerRoot as NSString).appendingPathComponent("Documents"),
             app.dataContainerURL.appendingPathComponent("Documents", conformingTo: .directory)),
            ((containerRoot as NSString).appendingPathComponent("Library/Preferences"),
             app.dataContainerURL.appendingPathComponent("Library", conformingTo: .directory)
                .appendingPathComponent("Preferences", conformingTo: .directory))
        ]

        var copied = 0
        for (sourcePath, destinationDir) in sources {
            guard let handle = try? BadQuery.consume(path: sourcePath, create: true) else { continue }
            handles.append(handle)
            guard fm.fileExists(atPath: sourcePath),
                  let items = try? fm.contentsOfDirectory(
                      at: URL(fileURLWithPath: sourcePath),
                      includingPropertiesForKeys: nil,
                      options: .skipsHiddenFiles
                  ) else { continue }

            try fm.createDirectory(at: destinationDir, withIntermediateDirectories: true)
            for item in items {
                if item.lastPathComponent == ".com.apple.mobile_container_manager.metadata.plist" {
                    continue
                }
                let dest = destinationDir.appendingPathComponent(item.lastPathComponent)
                if fm.fileExists(atPath: dest.path) {
                    try? fm.removeItem(at: dest)
                }
                if let handleForItem = try? BadQuery.consume(path: item.path, create: false) {
                    handles.append(handleForItem)
                }
                try fm.copyItem(at: item, to: dest)
                copied += 1
            }
        }
        return copied
    }

    // MARK: - Metadata

    private func loadMetadata() -> [String: Any] {
        guard let data = try? Data(contentsOf: metadataURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)
                as? [String: Any] else {
            return [:]
        }
        return plist
    }

    private func writeMetadata(_ meta: [String: Any]) throws {
        let data = try PropertyListSerialization.data(fromPropertyList: meta, format: .xml, options: 0)
        try data.write(to: metadataURL, options: .atomic)
    }

    // MARK: - Helpers

    private func ensureDirectories() throws {
        let fm = FileManager.default
        for dir in [rootURL, applicationsURL, dataURL, importsURL, exportsURL] {
            if !fm.fileExists(atPath: dir.path) {
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            }
        }
    }

    private static func readInfoPlist(_ bundleURL: URL) -> [String: Any] {
        (try? readInfoPlistThrowing(bundleURL)) ?? [:]
    }

    /// Locate the Info.plist of an app bundle: at the bundle root (iOS) or
    /// under Contents/ (macOS bundles). Directories named Info.plist don't
    /// count — those appear in mangled archives.
    private static func infoPlistURL(in bundleURL: URL) -> URL? {
        let fm = FileManager.default
        for candidate in ["Info.plist", "Contents/Info.plist"] {
            let url = bundleURL.appendingPathComponent(candidate)
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue {
                return url
            }
        }
        return nil
    }

    /// Reads and parses an app bundle's Info.plist, throwing a specific
    /// LiveContainerError when the file is missing, unreadable, or malformed
    /// so the user gets a useful message instead of a generic import failure.
    private static func readInfoPlistThrowing(_ bundleURL: URL) throws -> [String: Any] {
        guard let url = infoPlistURL(in: bundleURL) else {
            throw LiveContainerError.missingInfoPlist(bundleURL.path)
        }
        guard let data = try? Data(contentsOf: url) else {
            throw LiveContainerError.unreadableInfoPlist(bundleURL.path, "file could not be read")
        }
        // PropertyListSerialization handles both XML and binary Info.plists.
        if let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)
            as? [String: Any] {
            return plist
        }
        if let plist = NSDictionary(contentsOfFile: url.path) as? [String: Any] {
            return plist
        }
        throw LiveContainerError.unreadableInfoPlist(bundleURL.path, "not a valid property list")
    }

    /// Locate the .app bundle (a directory with an Info.plist) inside a zip
    /// extraction root, a Payload folder, or a directly imported app folder.
    private static func findAppBundle(in root: URL) -> URL? {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        ) else {
            return nil
        }

        // If the root itself is an app bundle, use it.
        if Self.infoPlistURL(in: root) != nil {
            return root
        }

        var checkedPayload = false
        for item in items {
            let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            guard isDir else { continue }

            if item.pathExtension.lowercased() == "app" {
                if Self.infoPlistURL(in: item) != nil {
                    return item
                }
            } else if item.lastPathComponent.lowercased() == "payload" && !checkedPayload {
                checkedPayload = true
                if let app = findAppBundle(in: item) { return app }
            }
        }

        // A single nested directory (e.g. the user picked the parent of an
        // extracted app folder) — look one level deeper.
        let appDirs = items.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false }
        if appDirs.count == 1 {
            return findAppBundle(in: appDirs[0])
        }
        return nil
    }

    /// Print a shallow tree of an extracted/picked folder so import failures
    /// can be debugged from the console log.
    private static func logLayout(at root: URL, label: String) {
        print("LiveContainer: \(label) at \(root.path)")
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        ) else {
            print("LiveContainer:   (could not list contents)")
            return
        }
        for item in items {
            let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            print("LiveContainer:   \(isDir ? "[dir] " : "[file]")\(item.lastPathComponent)")
        }
    }

    // MARK: - ZIP entry helpers
    //
    // Reading the zip straight from its entry list is far more tolerant than
    // extracting everything to disk first: archives with name conflicts or
    // odd directory entries (which make unzipItem abort) still work.

    /// Normalize a zip entry path: forward slashes, lowercased.
    private static func normalizedEntryPath(_ path: String) -> String {
        path.replacingOccurrences(of: "\\", with: "/").lowercased()
    }

    /// Find the folder path of the first ".app" bundle in a zip that has an
    /// Info.plist at its root (or under Contents/), e.g. "Payload/Foo.app/".
    private static func appFolderPath(in archive: Archive) -> String? {
        for entry in archive {
            let p = normalizedEntryPath(entry.path)
            guard let range = p.range(of: ".app/") else { continue }
            let folder = String(p[...range.upperBound]) // includes trailing "/"
            let relative = String(p[range.upperBound...])
            if relative == "info.plist" || relative == "contents/info.plist" {
                return folder
            }
        }
        return nil
    }

    /// Read an app bundle's Info.plist directly out of the zip, without
    /// relying on the extracted files on disk.
    private static func readInfoPlistFromArchive(_ archive: Archive?) throws -> (folder: String, plist: [String: Any]) {
        guard let archive = archive else {
            throw LiveContainerError.installFailed("Could not open the IPA archive.")
        }
        guard let folder = appFolderPath(in: archive) else {
            throw LiveContainerError.noAppInArchive("<archive>")
        }
        let wanted = normalizedEntryPath(folder)
        guard let entry = archive.first(where: {
            let p = normalizedEntryPath($0.path)
            return p == wanted + "info.plist" || p == wanted + "contents/info.plist"
        }) else {
            throw LiveContainerError.noAppInArchive("<archive>")
        }
        var data = Data()
        _ = try archive.extract(entry) { data.append($0) }
        guard let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)
            as? [String: Any] else {
            throw LiveContainerError.unreadableInfoPlist(entry.path, "not a valid property list in the archive")
        }
        return (folder: folder, plist: plist)
    }

    /// Extract every entry under `folderPath` in the archive into
    /// `destination`, skipping any entry that fails instead of aborting.
    private static func extractFolder(fromArchive archive: Archive, folderPath: String, to destination: URL) throws -> Bool {
        let fm = FileManager.default
        let slashFolder = folderPath.replacingOccurrences(of: "\\", with: "/")
        var extractedAny = false
        for entry in archive {
            let slashPath = entry.path.replacingOccurrences(of: "\\", with: "/")
            guard slashPath.lowercased().hasPrefix(slashFolder.lowercased()) else { continue }
            let relative = String(slashPath.dropFirst(slashFolder.count))
            guard !relative.isEmpty else { continue }
            let dest = destination.appendingPathComponent(relative)
            do {
                switch entry.type {
                case .directory:
                    try fm.createDirectory(at: dest, withIntermediateDirectories: true, attributes: nil)
                case .file, .symlink:
                    if fm.fileExists(atPath: dest.path) {
                        try? fm.removeItem(at: dest)
                    }
                    _ = try archive.extract(entry, to: dest)
                }
                extractedAny = true
            } catch {
                print("LiveContainer: skipped bad zip entry \(entry.path): \(error.localizedDescription)")
            }
        }
        return extractedAny
    }

    private static func sanitize(_ string: String) -> String {
        string.replacingOccurrences(of: "[/:]", with: "_", options: .regularExpression)
    }

    static func directorySize(at url: URL) -> Int64 {
        guard FileManager.default.fileExists(atPath: url.path) else { return 0 }
        let keys: [URLResourceKey] = [.fileSizeKey, .isDirectoryKey]
        var total: Int64 = 0
        if let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) {
            for case let fileURL as URL in enumerator {
                guard let values = try? fileURL.resourceValues(forKeys: Set(keys)) else { continue }
                if values.isDirectory != true {
                    total += Int64(values.fileSize ?? 0)
                }
            }
        }
        return total
    }

    /// Best-effort icon extraction from an app bundle's Info.plist.
    private static func loadIcon(from bundleURL: URL, info: [String: Any]) -> UIImage? {
        var names: [String] = []
        if let icons = info["CFBundleIcons"] as? [String: Any],
           let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
           let files = primary["CFBundleIconFiles"] as? [String] {
            names.append(contentsOf: files)
        }
        if let files = info["CFBundleIconFiles"] as? [String] {
            names.append(contentsOf: files)
        }
        if let iconName = info["CFBundleIconName"] as? String {
            names.insert(iconName, at: 0)
        }
        names.append(contentsOf: ["AppIcon60x60@2x", "AppIcon@2x", "Icon-60@2x", "icon@2x"])

        let fm = FileManager.default
        for name in names {
            let candidates = [
                name,
                "\(name)@2x",
                "\(name)@3x",
                "\(name).png",
                "\(name)@2x.png",
                "\(name)@3x.png"
            ]
            for candidate in candidates {
                let url = bundleURL.appendingPathComponent(candidate)
                if fm.fileExists(atPath: url.path) {
                    if let image = UIImage(contentsOfFile: url.path) { return image }
                }
            }
        }

        // Fallback: any root-level icon-looking PNG (AppIcon.png etc.).
        if let items = try? fm.contentsOfDirectory(at: bundleURL, includingPropertiesForKeys: nil) {
            for item in items where item.pathExtension.lowercased() == "png" {
                let lower = item.lastPathComponent.lowercased()
                if lower.contains("icon") || lower.hasPrefix("appicon") {
                    if let image = UIImage(contentsOfFile: item.path) { return image }
                }
            }
        }
        return nil
    }
}