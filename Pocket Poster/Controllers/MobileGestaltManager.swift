//
//  MobileGestaltManager.swift
//  Pocket Poster
//
//  MobileGestalt (MGA) tweak engine ported from rooootdev/mond:
//  - sandbox access via the bad_query container query route (probe_leaf variant)
//  - load/backup/apply/revert of com.apple.MobileGestalt.plist
//  - CacheData offset resolution (mg.swift) for binary-key tweaks
//

import Foundation
import Darwin
import UIKit
import MachO

enum MobileGestaltError: LocalizedError {
    case notLoaded
    case missingBackup
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .notLoaded:
            return "MobileGestalt.plist has not been loaded yet."
        case .missingBackup:
            return "No MobileGestalt backup found. Open this view once before Revert Tweaks."
        case .writeFailed(let reason):
            return "Failed to write MobileGestalt.plist: \(reason)"
        }
    }
}

final class MobileGestaltManager: ObservableObject {

    static let shared = MobileGestaltManager()

    // MARK: - Paths (same as mond)

    static let gestaltPath = "/private/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches/com.apple.MobileGestalt.plist"
    static let gestaltDir  = "/private/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches/"

    // MARK: - Published State

    /// The loaded, mutable MobileGestalt dictionary (CacheExtra / CacheData).
    @Published private(set) var dictionary: NSMutableDictionary = NSMutableDictionary()
    @Published private(set) var isValid = true
    @Published private(set) var isEmpty = false
    @Published private(set) var isLoading = false

    /// Original values captured from the first backup (for "Original" subtype etc).
    @Published private(set) var originalSubtype = 0
    @Published private(set) var originalDeviceName = ""

    /// Last load/apply error, if any (surfaced in the UI).
    @Published var lastError: String?

    var isLoaded: Bool { dictionary.count > 0 }

    /// Convenience accessor for the CacheExtra mutable dictionary inside the loaded plist.
    var cacheExtra: NSMutableDictionary? {
        dictionary["CacheExtra"] as? NSMutableDictionary
    }

    // MARK: - Private

    private var grantHandle: BadQueryHandle?
    private var cacheOffsets: [String: Int] = [:]

    // MARK: - Backup URL

    var backupURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let backups = base.appendingPathComponent("backups", isDirectory: true)
        try? FileManager.default.createDirectory(at: backups, withIntermediateDirectories: true)
        return backups.appendingPathComponent("SavedGestalt.plist")
    }

    // MARK: - Sandbox Access

    /// Obtains a sandbox extension to the MobileGestalt Caches directory
    /// (mond's grant_mg route). The handle is kept for the process lifetime,
    /// matching mond — FileManager operations below the granted path keep working.
    @discardableResult
    func grantAccess() throws -> BadQueryHandle {
        if let grantHandle { return grantHandle }

        let handle = try BadQuery.consume(
            path: Self.gestaltDir,
            create: false,
            groupIdentifier: nil,
            isGroup: false,
            probeLeaf: "com.apple.MobileGestalt.plist"
        )
        grantHandle = handle
        return handle
    }

    // MARK: - Load

    /// Loads the plist off the main thread, backs up the original on first run,
    /// and captures the original artwork values.
    func load() {
        guard !isLoading, dictionary.count == 0 else { return }
        isLoading = true

        do {
            try grantAccess()
        } catch {
            isLoading = false
            lastError = error.localizedDescription
            setIsValid(false)
            return
        }

        let gestaltPath = Self.gestaltPath
        let backupURL = self.backupURL
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let fileSize = (try? FileManager.default.attributesOfItem(atPath: gestaltPath))?[.size] as? UInt64 ?? 0
            guard let loaded = NSMutableDictionary(contentsOfFile: gestaltPath) else {
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.isLoading = false
                    self.isEmpty = fileSize == 0
                    self.setIsValid(false)
                    self.lastError = "Failed to load MobileGestalt.plist. Restart the app and try again."
                }
                return
            }

            // Back up the original gestalt to a safe place on first run.
            if !FileManager.default.fileExists(atPath: backupURL.path) {
                try? FileManager.default.copyItem(atPath: gestaltPath, toPath: backupURL.path)
            }

            var ogSubtype = 0
            var ogName = ""
            if let saved = NSMutableDictionary(contentsOfFile: backupURL.path),
               let ogExtra = saved["CacheExtra"] as? NSMutableDictionary,
               let ogArt = ogExtra["oPeik/9e8lQWMszEjbPzng"] as? NSMutableDictionary {
                ogSubtype = ogArt["ArtworkDeviceSubType"] as? Int ?? 0
                ogName = ogArt["ArtworkDeviceProductDescription"] as? String ?? ""
            }

            DispatchQueue.main.async {
                guard let self else { return }
                self.dictionary = loaded
                self.originalSubtype = ogSubtype
                self.originalDeviceName = ogName
                self.isLoading = false
                self.isEmpty = fileSize == 0
                self.setIsValid(true)
            }
        }
    }

    private func setIsValid(_ valid: Bool) {
        isValid = valid
    }

    // MARK: - Apply / Revert

    /// Serializes the loaded dictionary back to the MobileGestalt plist.
    func apply() throws {
        guard dictionary.count > 0 else { throw MobileGestaltError.notLoaded }
        let data = try PropertyListSerialization.data(fromPropertyList: dictionary, format: .xml, options: 0)
        try write(data)
        dictionary = NSMutableDictionary()
    }

    /// Restores the first-run backup.
    func revert() throws {
        guard FileManager.default.fileExists(atPath: backupURL.path) else {
            throw MobileGestaltError.missingBackup
        }
        let data = try Data(contentsOf: backupURL)
        try write(data)
    }

    /// Atomically replaces the MobileGestalt plist (temp file + replace).
    private func write(_ data: Data) throws {
        do {
            try grantAccess()
        } catch {
            throw MobileGestaltError.writeFailed(error.localizedDescription)
        }

        let targetURL = URL(fileURLWithPath: Self.gestaltPath)
        let tempURL = targetURL.deletingLastPathComponent()
            .appendingPathComponent(".\(targetURL.lastPathComponent).\(UUID().uuidString).tmp")

        do {
            try data.write(to: tempURL, options: .withoutOverwriting)
            defer { try? FileManager.default.removeItem(at: tempURL) }

            if FileManager.default.fileExists(atPath: targetURL.path) {
                _ = try FileManager.default.replaceItemAt(targetURL, withItemAt: tempURL)
            } else {
                try FileManager.default.moveItem(at: tempURL, to: targetURL)
            }
        } catch {
            throw MobileGestaltError.writeFailed(error.localizedDescription)
        }
    }

    // MARK: - CacheData (binary blob) helpers

    /// Locates the offset of a MobileGestalt key inside the CacheData binary blob
    /// (port of mond's mg.swift `cache_data_offset`).
    func cacheDataOffset(for key: String) -> Int {
        if let cached = cacheOffsets[key] {
            return cached
        }

        let libMG = "/usr/lib/libMobileGestalt.dylib"
        dlopen(libMG, RTLD_GLOBAL)

        var header: UnsafePointer<mach_header_64>?
        for i in 0..<_dyld_image_count() {
            if String(cString: _dyld_get_image_name(i)) == libMG {
                header = unsafeBitCast(_dyld_get_image_header(i), to: UnsafePointer<mach_header_64>.self)
                break
            }
        }
        guard let header else {
            cacheOffsets[key] = 0
            return 0
        }

        var textSize = 0
        guard let cstring = getsectiondata(header, "__TEXT", "__cstring", &textSize) else {
            cacheOffsets[key] = 0
            return 0
        }
        let cstr = cstring.withMemoryRebound(to: CChar.self, capacity: textSize) { $0 }

        var keyPtr = cstr
        while Int(keyPtr - cstr) < textSize {
            if String(cString: keyPtr) == key { break }
            keyPtr += strlen(keyPtr) + 1
        }

        var constSize = 0
        var ptr = getsectiondata(header, "__AUTH_CONST", "__const", &constSize)?
            .withMemoryRebound(to: UInt.self, capacity: constSize / 8) { $0 }
        if ptr == nil {
            ptr = getsectiondata(header, "__DATA_CONST", "__const", &constSize)?
                .withMemoryRebound(to: UInt.self, capacity: constSize / 8) { $0 }
        }

        guard let ptr else {
            cacheOffsets[key] = 0
            return 0
        }

        for i in 0..<constSize / 8 {
            if ptr[i] == UInt(bitPattern: keyPtr) {
                let offset = Int((ptr.advanced(by: i).withMemoryRebound(to: UInt16.self, capacity: 1) { $0[0x9a / 2] }) << 3)
                cacheOffsets[key] = offset
                return offset
            }
        }

        cacheOffsets[key] = 0
        return 0
    }

    /// Reads an Int from CacheData at the resolved key offset (0 if unavailable).
    func cacheDataInt(for key: String) -> Int {
        guard let cacheData = dictionary["CacheData"] as? NSMutableData else { return 0 }
        let offset = cacheDataOffset(for: key)
        guard offset > 0 else { return 0 }
        return cacheData.bytes.load(fromByteOffset: offset, as: Int.self)
    }

    /// Writes an Int into CacheData at the resolved key offset.
    /// Returns false if the offset could not be resolved (unsupported iOS).
    @discardableResult
    func setCacheDataInt(_ value: Int, for key: String) -> Bool {
        guard let cacheData = dictionary["CacheData"] as? NSMutableData else { return false }
        let offset = cacheDataOffset(for: key)
        guard offset > 0 else { return false }
        cacheData.mutableBytes.storeBytes(of: value, toByteOffset: offset, as: Int.self)
        return true
    }
}

// MARK: - Device Helpers (ported from mond)

/// e.g. 18.2 -> 18.2, 26.0 -> 26.0
func doubleSystemVersion() -> Double {
    let v = ProcessInfo.processInfo.operatingSystemVersion
    return Double(v.majorVersion) + Double(v.minorVersion) / 10
}

func machineName() -> String {
    var systemInfo = utsname()
    uname(&systemInfo)
    let mirror = Mirror(reflecting: systemInfo.machine)
    return mirror.children.reduce("") { identifier, element in
        guard let value = element.value as? Int8, value != 0 else { return identifier }
        return identifier + String(UnicodeScalar(UInt8(value)))
    }
}

func hasHomeButton() -> Bool {
    let windows = UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .flatMap { $0.windows }

    return (windows.first(where: { $0.isKeyWindow })?.safeAreaInsets.bottom ?? 0) == 0
}