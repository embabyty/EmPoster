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
    case missingInfoPlist
    case badQueryUnavailable
    case exportFailed
    case installFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidBundle:
            return "This is not a valid app bundle. Import an .ipa or an .app."
        case .missingInfoPlist:
            return "The app bundle has no Info.plist."
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

        // Resolve the actual .app bundle from an .ipa archive or a raw .app.
        let sourceBundle: URL
        if url.pathExtension.lowercased() == "ipa" {
            let tmp = importsURL.appendingPathComponent(UUID().uuidString, conformingTo: .directory)
            try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: tmp) }
            try fm.unzipItem(at: url, to: tmp)
            let payload = tmp.appendingPathComponent("Payload", conformingTo: .directory)
            guard let entries = try? fm.contentsOfDirectory(
                at: payload,
                includingPropertiesForKeys: nil,
                options: .skipsHiddenFiles
            ) else { throw LiveContainerError.invalidBundle }
            guard let app = entries.first(where: { $0.pathExtension == "app" }) else {
                throw LiveContainerError.invalidBundle
            }
            sourceBundle = app
        } else if url.pathExtension.lowercased() == "app"
                    || ((try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false) {
            sourceBundle = url
        } else {
            throw LiveContainerError.invalidBundle
        }

        let info = Self.readInfoPlist(sourceBundle)
        guard let bundleID = info["CFBundleIdentifier"] as? String, !bundleID.isEmpty else {
            throw LiveContainerError.missingInfoPlist
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
        NSDictionary(contentsOfFile: bundleURL.appendingPathComponent("Info.plist").path) as? [String: Any] ?? [:]
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