//
//  SettingsView.swift
//  EmPoster
//
//  Created by lemin on 6/1/25.
//

import SwiftUI

struct SettingsView: View {
    // Prefs
    @AppStorage("pbHash") var pbHash: String = "" // PosterBoard hash
    @AppStorage("cpHash") var cpHash: String = "" // CarPlay hash
    @AppStorage("ignoreDurationLimit") var ignoreDurationLimit: Bool = false
    
    @ObservedObject private var patreonManager = PatreonManager.shared
    
    @State var checkingForHash: Bool = false
    @State var hashCheckTask: Task<Void, any Error>? = nil
    @State var detectingOnDevice: Bool = false
    @State var showSubscriptionSheet: Bool = false
    
    var body: some View {
        List {
            // MARK: EmPoster Pro
            Section {
                if !patreonManager.isDeviceAuthorized {
                    HStack(spacing: 12) {
                        Image(systemName: "lock.fill")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("EmPoster Pro")
                                .font(.headline)
                            Text("Not available on this device.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .foregroundStyle(Color(uiColor: .label))
                } else if patreonManager.isPro {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.title2)
                            .foregroundStyle(.green)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("EmPoster Pro is Active")
                                .font(.headline)
                            if patreonManager.isLoggedIn {
                                Text([
                                    patreonManager.memberName,
                                    patreonManager.tier
                                ].compactMap { $0 }.joined(separator: " · "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                    }
                    Button(action: {
                        patreonManager.logOut()
                    }) {
                        Text("Log Out")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                } else {
                    Button(action: {
                        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                        showSubscriptionSheet = true
                    }) {
                        HStack(spacing: 12) {
                            Image(systemName: "crown.fill")
                                .font(.title2)
                                .foregroundStyle(.yellow)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Subscribe on Patreon")
                                    .font(.headline)
                                Text("Support the app and unlock Pro wallpapers, videos & MGA tools.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }
                    .foregroundStyle(Color(uiColor: .label))

                    Button(action: {
                        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                        patreonManager.login()
                    }) {
                        HStack(spacing: 12) {
                            Image(systemName: "person.badge.key")
                                .font(.title2)
                                .foregroundStyle(.orange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Login with Patreon")
                                    .font(.headline)
                                Text("Already a patron? Log in to unlock Pro.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }
                    .foregroundStyle(Color(uiColor: .label))
                }
            } header: {
                Label("EmPoster Pro", systemImage: "crown")
            }
            .sheet(isPresented: $showSubscriptionSheet) {
                SubscriptionView()
            }
            
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("Enter PosterBoard App Hash", text: $pbHash)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .font(.system(.body, design: .monospaced))
                    if CarPlayManager.supportsCarPlay() {
                        TextField("Enter CarPlayWallpaper App Hash", text: $cpHash)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .font(.system(.body, design: .monospaced))
                    }
                    
                    if SymHandler.prefersBadQuery {
                        Text("bad_query available — on-device detect works (no PC).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    HStack {
                        Spacer()
                        // On-device detect via bad_query (iOS 26/27)
                        if SymHandler.prefersBadQuery {
                            Button(action: {
                                detectOnDevice()
                            }) {
                                if detectingOnDevice {
                                    ProgressView()
                                } else {
                                    Text("Detect On-Device")
                                }
                            }
                            .foregroundStyle(.blue)
                            .disabled(detectingOnDevice)
                        }
                        
                        // Run task to check until file exists from Nugget pc over AFC
                        Button(action: {
                            if !FileManager.default.fileExists(atPath: SymHandler.getPosterBoardHashURL().path()) {
                                // don't show the alert because it is already there
                                UIApplication.shared.confirmAlert(title: NSLocalizedString("Waiting for app hash...", comment: ""), body: NSLocalizedString("Connect your device to Nugget and click the \"Pocket Poster Helper\" button.", comment: ""), confirmTitle: NSLocalizedString("Cancel", comment: ""), onOK: {
                                    cancelWaitForHash()
                                }, noCancel: true)
                            }
                            startWaitForHash()
                        }) {
                            Text(SymHandler.prefersBadQuery ? "Detect via Nugget" : "Detect")
                        }
                        .foregroundStyle(.green)
                        .onChange(of: checkingForHash) { _ in
                            if !checkingForHash {
                                // hide ui alert
                                UIApplication.shared.dismissAlert(animated: true)
                            }
                        }
                    }
                }
            } header: {
                Label("App Hash", systemImage: "lock.app.dashed")
            }
            
            Section {
                if patreonManager.isPro {
                    HStack {
                        Label("Disable Video Duration Limit", systemImage: "ruler")
                        Spacer()
                        Toggle("", isOn: $ignoreDurationLimit)
                            .labelsHidden()
                    }
                } else {
                    Button(action: {
                        showSubscriptionSheet = true
                    }) {
                        HStack {
                            Label("Disable Video Duration Limit", systemImage: "ruler")
                            Spacer()
                            Image(systemName: "lock.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .foregroundStyle(Color(uiColor: .label))
                }
            } header: {
                Label("Preferences", systemImage: "gear")
            }
            
            Section {
                Button(action: {
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                    UserDefaults.standard.set(false, forKey: "finishedTutorial")
                }) {
                    Label("Replay Tutorial", systemImage: "questionmark.circle")
                }
                
                Button(action: {
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                    do {
                        try PosterBoardManager.clearCache()
                        Haptic.shared.notify(.success)
                        UIApplication.shared.alert(title: NSLocalizedString("App Cache Successfully Cleared!", comment: ""), body: "")
                    } catch {
                        Haptic.shared.notify(.error)
                        UIApplication.shared.alert(body: error.localizedDescription)
                    }
                }) {
                    Label("Clear App Cache", systemImage: "trash.circle")
                }
                .foregroundStyle(.red)
                
                Button(action: {
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                    UserDefaults.standard.set(nil, forKey: "ActiveCarPlayWallpapers")
                    try? FileManager.default.removeItem(at: CarPlayManager.getCarPlayPhotosURL())
                    Haptic.shared.notify(.success)
                    UIApplication.shared.alert(title: NSLocalizedString("CarPlay Applied Wallpapers Successfully Cleared!", comment: ""), body: "")
                }) {
                    Label("Reset CarPlay Applied Wallpapers", systemImage: "trash.circle")
                }
                .foregroundStyle(.red)
            } header: {
                Label("Actions", systemImage: "gear")
            }
            
            // MARK: Links
            Section {
                if let scURL = URL(string: PosterBoardManager.ShortcutURL) {
                    Link(destination: scURL) {
                        Label("Download Fallback Shortcut", systemImage: "arrow.down.circle")
                    }
                }
                if let fbURL = URL(string: "shortcuts://run-shortcut?name=PosterBoard&input=text&text=troubleshoot") {
                    Link(destination: fbURL) {
                        Label("Create Additional Fallback Method", systemImage: "appclip")
                    }
                }
                if let nURL = URL(string: "https://github.com/leminlimez/Nugget") {
                    Link(destination: nURL) {
                        Label("Nugget GitHub", image: "github.fill")
                    }
                }
            } header: {
                Label("Links", systemImage: "link")
            }
            
            // MARK: Socials
            Section {
                Link(destination: URL(string: "https://github.com/leminlimez/Pocket-Poster")!) {
                    Label("View on GitHub", image: "github.fill")
                }
                Link(destination: URL(string: "https://discord.gg/MN8JgqSAqT")!) {
                    Label("Join the Discord", image: "discord.fill")
                }
                Link(destination: URL(string: "https://ko-fi.com/leminlimez")!) {
                    Label("Support on Ko-Fi", image: "ko-fi")
                }
            } header: {
                Label("Socials", systemImage: "globe")
            }
            
            // MARK: Credits
            Section {
                LinkCell(imageName: "Mak5er", url: "https://github.com/Mak5er", title: "Mak5er", contribution: "bad_query port · iOS 27 build", circle: true)
                LinkCell(imageName: "leminlimez", url: "https://github.com/leminlimez", title: "LeminLimez", contribution: NSLocalizedString("Main Developer", comment: "leminlimez's contribution"), circle: true)
                LinkCell(imageName: "serstars", url: "https://github.com/SerStars", title: "SerStars", contribution: NSLocalizedString("Website Designer", comment: ""), circle: true)
                LinkCell(imageName: "Nathan", url: "https://github.com/verygenericname", title: "Nathan", contribution: NSLocalizedString("Exploit (.Trash)", comment: ""), circle: true)
                LinkCell(imageName: "duy", url: "https://github.com/khanhduytran0", title: "DuyKhanhTran", contribution: NSLocalizedString("Exploit (.Trash)", comment: ""), circle: true)
                LinkCell(imageName: "sky", url: "https://github.com/forcequitOS/bad_query", title: "forcequitOS", contribution: "bad_query (iOS 26/27)", circle: false)
                LinkCell(imageName: "sky", url: "https://bsky.app/profile/did:plc:xykfeb7ieeo335g3aly6vev4", title: "dootskyre", contribution: NSLocalizedString("Fallback Shortcut Creator", comment: ""), circle: true)
                LinkCell(imageName: "POEditor", url: "https://poeditor.com/join/project/MPZOsunwVj", title: NSLocalizedString("Community Translators", comment: ""), contribution: "POEditor")
            } header: {
                Label("Credits", systemImage: "wrench.and.screwdriver")
            }
        }
    }
    
    /// Scan containers on-device with bad_query / fsgetpath — no computer needed.
    func detectOnDevice() {
        detectingOnDevice = true
        UIApplication.shared.alert(
            title: "Scanning containers…",
            body: "Looking for PosterBoard via bad_query. This may take a moment.",
            animated: true,
            withButton: false
        )
        
        DispatchQueue.global(qos: .userInitiated).async {
            var pb: String?
            var cp: String?
            var errMsg: String?
            
            do {
                pb = try BadQuery.findPosterBoardHash()
            } catch {
                errMsg = error.localizedDescription
            }
            
            if CarPlayManager.supportsCarPlay() {
                cp = try? BadQuery.findCarPlayHash()
            }
            
            // Always show a closeable result alert (loading alert has no OK button —
            // dismiss must complete before the next alert is presented).
            DispatchQueue.main.async {
                detectingOnDevice = false
                
                if let pb {
                    pbHash = pb.trimmingCharacters(in: .whitespacesAndNewlines)
                    if let cp {
                        cpHash = cp.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    Haptic.shared.notify(.success)
                    let body = cp != nil
                        ? "PosterBoard:\n\(pbHash)\n\nCarPlay:\n\(cpHash)"
                        : "PosterBoard:\n\(pbHash)"
                    // alert() auto-dismisses any previous (buttonless) sheet first
                    UIApplication.shared.alert(title: "Hash found!", body: body, withButton: true)
                } else {
                    Haptic.shared.notify(.error)
                    UIApplication.shared.alert(
                        title: "Detect failed",
                        body: errMsg ?? "Could not find PosterBoard container. Open Wallpaper settings once, then retry.",
                        withButton: true
                    )
                }
            }
        }
    }
    
    func startWaitForHash() {
        checkingForHash = true
        hashCheckTask = Task {
            let filePath = SymHandler.getPosterBoardHashURL()
            while !FileManager.default.fileExists(atPath: filePath.path()) {
                try? await Task.sleep(nanoseconds: 500_000_000) // Sleep 0.5s
                try Task.checkCancellation()
            }
            
            do {
                let contents = try String(contentsOf: filePath)
                try? FileManager.default.removeItem(at: filePath)
                await MainActor.run {
                    pbHash = contents
                }
                // check for carplay hash
                if UIDevice.current.userInterfaceIdiom == .phone {
                    let carplayPath = SymHandler.getCarPlayHashURL()
                    if FileManager.default.fileExists(atPath: carplayPath.path()) {
                        let carplayContents = try String(contentsOf: carplayPath)
                        try? FileManager.default.removeItem(at: carplayPath)
                        await MainActor.run {
                            cpHash = carplayContents
                        }
                    }
                }
            } catch {
                print(error.localizedDescription)
            }

            await MainActor.run {
                checkingForHash = false
                hashCheckTask = nil
            }
        }
    }
    
    func cancelWaitForHash() {
        hashCheckTask?.cancel()
        hashCheckTask = nil
        checkingForHash = false
    }
}
