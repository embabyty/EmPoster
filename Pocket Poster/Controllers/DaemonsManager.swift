//
//  DaemonsManager.swift
//  EmPoster
//
//  Nugget-style "Daemons" tweak, applied on-device via the bad_query sandbox
//  escape (no PC, no BookRestore). Disabled daemons are written as `true`
//  entries into /var/db/com.apple.xpc.launchd/disabled.plist so launchd skips
//  them on boot — the same mechanism as Nugget's AdvancedPlistTweak. Also
//  optionally nullifies ScreenTimeAgent.plist so Screen Time can't lock apps
//  via iCloud.
//

import Foundation

enum DaemonsError: LocalizedError {
    case nothingToApply
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .nothingToApply:
            return "Turn on \"Modify Daemons\" or select a daemon to disable first."
        case .writeFailed(let reason):
            return "Failed to write daemon preferences: \(reason)"
        }
    }
}

/// One toggle from Nugget's Daemons menu.
struct DaemonToggle: Identifiable {
    let id: String
    let title: String
    /// Optional explanation shown behind the info button.
    let info: String?
    /// Daemon bundle IDs that are disabled in disabled.plist when the toggle is on.
    let bundleIDs: [String]
    /// When true, this toggle nullifies ScreenTimeAgent.plist instead.
    let clearsScreenTimeFile: Bool

    init(_ id: String, title: String, info: String? = nil, daemons: [String], clearsScreenTimeFile: Bool = false) {
        self.id = id
        self.title = title
        self.info = info
        self.bundleIDs = daemons
        self.clearsScreenTimeFile = clearsScreenTimeFile
    }
}

/// A grouped section of DaemonToggles (mirrors Nugget's menu separators).
struct DaemonGroup: Identifiable {
    let id: String
    let title: String
    let icon: String
    let toggles: [DaemonToggle]
}

extension DaemonGroup {
    /// The full Daemons menu, ported from Nugget (daemon IDs + descriptions
    /// from `tweaks/daemons_tweak.py` and the Daemons page in `mainwindow.ui`).
    static let all: [DaemonGroup] = [
        DaemonGroup(
            id: "logging",
            title: "Logging & Monitoring",
            icon: "waveform.path.ecg",
            toggles: [
                DaemonToggle(
                    "thermalmonitord",
                    title: "Disable thermalmonitord",
                    info: "Disables the temperature monitoring daemon to reduce system checks.\n\nWarning: Disabling will cause the battery to show \"Unknown Part\" or \"Unverified\" in Settings.",
                    daemons: ["com.apple.thermalmonitord"]
                ),
                DaemonToggle(
                    "ota",
                    title: "Disable OTA",
                    info: "Stops over-the-air updates to prevent auto-downloads.",
                    daemons: [
                        "com.apple.mobile.softwareupdated",
                        "com.apple.OTATaskingAgent",
                        "com.apple.softwareupdateservicesd",
                        "com.apple.mobile.NRDUpdated"
                    ]
                ),
                DaemonToggle(
                    "usageTrackingAgent",
                    title: "Disable UsageTrackingAgent",
                    info: "Disables usage tracking for improved privacy.",
                    daemons: ["com.apple.UsageTrackingAgent"]
                ),
                DaemonToggle(
                    "screenTime",
                    title: "Disable Screen Time Agent",
                    info: "Disables Screen Time monitoring features.",
                    daemons: [
                        "com.apple.ScreenTimeAgent",
                        "com.apple.homed",
                        "com.apple.familycircled",
                        "com.apple.familynotification",
                        "com.apple.asktod"
                    ]
                ),
                DaemonToggle(
                    "clearScreenTimeAgent",
                    title: "Clear ScreenTimeAgent.plist file",
                    info: "Deletes the Screen Time Agent preferences file to prevent app lockout set via iCloud.\n\nTo work properly, also disable the daemon using the toggle above.",
                    daemons: [],
                    clearsScreenTimeFile: true
                ),
                DaemonToggle(
                    "crashReports",
                    title: "Disable Logs, Dumps, and Crash Reports",
                    info: "Stops logs, dumps, and crash reports collection.",
                    daemons: [
                        "com.apple.ReportCrash",
                        "com.apple.ReportCrash.Jetsam",
                        "com.apple.ReportMemoryException",
                        "com.apple.OTACrashCopier",
                        "com.apple.analyticsd",
                        "com.apple.wifianalyticsd",
                        "com.apple.aslmanager",
                        "com.apple.coresymbolicationd",
                        "com.apple.crash_mover",
                        "com.apple.crashreportcopymobile",
                        "com.apple.DumpBasebandCrash",
                        "com.apple.DumpPanic",
                        "com.apple.logd",
                        "com.apple.logd.admin",
                        "com.apple.logd.events",
                        "com.apple.logd.watchdog",
                        "com.apple.logd_helper",
                        "com.apple.logd_reporter",
                        "com.apple.logd_reporter.report_statistics",
                        "com.apple.system.logger",
                        "com.apple.hangreporter",
                        "com.apple.hangtracerd",
                        "com.apple.spindump",
                        "com.apple.tailspind",
                        "com.apple.rtcreportingd",
                        "com.apple.syslogd",
                        "com.apple.signpost.signpost_reporter",
                        "com.apple.pluginkit.pkreporter",
                        "com.apple.ProxiedCrashCopier",
                        "com.apple.ProxiedCrashCopier.ProxyingDevice",
                        "com.apple.ReportSystemMemory"
                    ]
                ),
                DaemonToggle(
                    "diagnostics",
                    title: "Disable System Diagnostics",
                    info: "Disables tools that monitor and test hardware or system behavior for faults and performance issues.",
                    daemons: [
                        "com.apple.diagnosticd",
                        "com.apple.diagnosticextensionsd",
                        "com.apple.diagnosticservicesd",
                        "com.apple.diagnosticspushd",
                        "com.apple.symptomsd-diag",
                        "com.apple.sysdiagnose",
                        "com.apple.sysdiagnose.darwinos",
                        "com.apple.sysdiagnose_helper"
                    ]
                ),
                DaemonToggle(
                    "atwakeup",
                    title: "Disable ATWAKEUP",
                    info: "Disables pinging to sleeping bluetooth devices for improved battery life.",
                    daemons: ["com.apple.atc.atwakeup"]
                )
            ]
        ),
        DaemonGroup(
            id: "services",
            title: "Services",
            icon: "server.rack",
            toggles: [
                DaemonToggle(
                    "gameCenter",
                    title: "Disable Game Center",
                    info: "Turns off Game Center background services.",
                    daemons: ["com.apple.gamed"]
                ),
                DaemonToggle(
                    "tips",
                    title: "Disable Tips Services",
                    info: "Disables the Tips service and notifications.",
                    daemons: ["com.apple.tipsd"]
                ),
                DaemonToggle(
                    "vpn",
                    title: "Disable VPN Service",
                    info: "Disables the Virtual Private Network service.",
                    daemons: ["com.apple.racoon"]
                ),
                DaemonToggle(
                    "location",
                    title: "Disable Location Services",
                    info: "Disables the Location Services daemon used by GPS, Maps, Weather, Find My, and apps that request location access.",
                    daemons: ["com.apple.locationd"]
                ),
                DaemonToggle(
                    "chineseLan",
                    title: "Disable Chinese WLAN Service",
                    info: "Disables the service that deals with errors with WiFi networks with Chinese characters in the name.",
                    daemons: ["com.apple.wapic", "com.apple.wifi.wapic"]
                ),
                DaemonToggle(
                    "healthKit",
                    title: "Disable HealthKit",
                    info: "Disables HealthKit services used by the health app.",
                    daemons: ["com.apple.healthd"]
                )
            ]
        ),
        DaemonGroup(
            id: "appServices",
            title: "App Services",
            icon: "square.grid.2x2",
            toggles: [
                DaemonToggle("airprint", title: "Disable AirPrint", daemons: ["com.apple.printd"]),
                DaemonToggle("assistiveTouch", title: "Disable Assistive Touch", daemons: ["com.apple.assistivetouchd"]),
                DaemonToggle("icloud", title: "Disable iCloud", daemons: ["com.apple.itunescloudd"]),
                DaemonToggle("hotspot", title: "Disable Internet Tethering (Hotspot)", daemons: ["com.apple.MobileInternetSharing"]),
                DaemonToggle("passbook", title: "Disable Passbook", daemons: ["com.apple.passd"]),
                DaemonToggle(
                    "spotlight",
                    title: "Disable Spotlight",
                    daemons: [
                        "com.apple.searchd",
                        "com.apple.corespotlightservice",
                        "com.apple.spotlightknowledged",
                        "com.apple.spotlightknowledged.updater",
                        "com.apple.spotlight.IndexAgent"
                    ]
                ),
                DaemonToggle(
                    "voiceControl",
                    title: "Disable Voice Control",
                    daemons: [
                        "com.apple.assistant_service",
                        "com.apple.assistantd",
                        "com.apple.voiced"
                    ]
                ),
                DaemonToggle("nanoTimeKit", title: "Disable NanoTimeKit (Apple Watch Face Sync)", daemons: ["com.apple.nanotimekitcompaniond"]),
                DaemonToggle("followUp", title: "Disable FollowUp", daemons: ["com.apple.followupd"])
            ]
        )
    ]
}

final class DaemonsManager: ObservableObject {
    static let shared = DaemonsManager()

    // MARK: - Paths (same as Nugget)

    /// Daemons launchd must not start; entries are `bundleID: true`.
    static let disabledPlistPath = "/var/db/com.apple.xpc.launchd/disabled.plist"
    /// Nullified when "Clear ScreenTimeAgent.plist file" is enabled.
    static let screenTimePlistPath = "/var/mobile/Library/Preferences/ScreenTimeAgent.plist"

    /// Entries Nugget always includes when applying the Daemons tweak.
    static let defaultEntries: [String: Bool] = [
        "com.apple.magicswitchd.companion": true,
        "com.apple.security.otpaird": true,
        "com.apple.dhcp6d": true,
        "com.apple.bootpd": true,
        "com.apple.ftp-proxy-embedded": false,
        "com.apple.relevanced": true
    ]

    // MARK: - State

    /// Checks as a set of DaemonToggle ids.
    @Published private(set) var enabledToggles: Set<String> = []
    @Published var isModifyingDaemons = false
    @Published var clearScreenTimeFile = false

    func setToggle(_ toggle: DaemonToggle, enabled: Bool) {
        if enabled {
            enabledToggles.insert(toggle.id)
            // Nugget auto-enables "Modify Daemons" when a daemon is toggled.
            isModifyingDaemons = true
        } else {
            enabledToggles.remove(toggle.id)
        }
    }

    // MARK: - Apply (bad_query)

    /// Writes the daemon changes to the device via the bad_query sandbox
    /// escape. File work happens off the main actor.
    func apply() async throws {
        let modify = isModifyingDaemons
        let clearScreenTime = clearScreenTimeFile
        guard modify || clearScreenTime else { throw DaemonsError.nothingToApply }

        // Build the same dict Nugget writes: the defaults plus every daemon
        // toggle (checked -> disabled true, unchecked -> explicitly enabled).
        var dict = Self.defaultEntries
        if modify {
            for group in DaemonGroup.all {
                for toggle in group.toggles where !toggle.clearsScreenTimeFile {
                    let disabled = enabledToggles.contains(toggle.id)
                    for bundleID in toggle.bundleIDs {
                        dict[bundleID] = disabled
                    }
                }
            }
        }
        let data = try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)

        try await Task.detached(priority: .userInitiated) {
            if modify {
                try Self.write(data, to: Self.disabledPlistPath)
            }
            if clearScreenTime {
                try Self.write(Data(), to: Self.screenTimePlistPath)
            }
        }.value
    }

    /// Atomically replaces `path` (temp file + rename) while holding a
    /// bad_query sandbox extension for its parent directory.
    private static func write(_ data: Data, to path: String) throws {
        let dirPath = (path as NSString).deletingLastPathComponent
        let handle = try BadQuery.consume(path: dirPath, create: true)
        defer { handle.release() }

        let targetURL = URL(fileURLWithPath: path)
        let tempURL = URL(fileURLWithPath: dirPath)
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
            throw DaemonsError.writeFailed(error.localizedDescription)
        }
    }
}