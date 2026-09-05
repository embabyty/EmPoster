//
//  AppsView.swift
//  EmPoster
//
//  LiveContainer-style app library (Pro). Apps are installed into EmPoster's
//  own container — never onto the iDevice — and can be run by handing the IPA
//  to LiveContainer (or another sideloader) via the share sheet.
//

import SwiftUI
import UniformTypeIdentifiers
import UIKit

/// Wrapper for presenting UIActivityViewController from SwiftUI.
struct ShareItems: Identifiable {
    let id = UUID()
    let items: [Any]
}

struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct AppsView: View {
    @ObservedObject private var patreonManager = PatreonManager.shared
    @ObservedObject private var lcManager = LiveContainerManager.shared

    @State private var showImporter = false
    @State private var showSubscriptionSheet = false
    @State private var shareItems: ShareItems?

    private let ipaType: UTType = UTType(filenameExtension: "ipa") ?? UTType(exportedAs: "com.embabyty.ipa")

    var body: some View {
        NavigationStack {
            Group {
                if patreonManager.isPro {
                    proContent
                } else {
                    lockedProSection
                }
            }
            .navigationTitle("Apps")
        }
        .sheet(item: $shareItems) { items in
            ActivityView(items: items.items)
        }
        .sheet(isPresented: $showSubscriptionSheet) {
            SubscriptionView()
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [ipaType, .applicationBundle],
            allowsMultipleSelection: true,
            onCompletion: handleImport
        )
    }

    // MARK: - Pro content

    private var proContent: some View {
        Group {
            if lcManager.apps.isEmpty {
                emptyState
            } else {
                List {
                    Section {
                        ForEach(lcManager.apps) { app in
                            AppRow(app: app, onRun: { run(app) })
                                .contextMenu { contextMenu(for: app) }
                        }
                        .onDelete(perform: uninstallApps)
                    } header: {
                        Label("Installed in EmPoster's container", systemImage: "shippingbox")
                    } footer: {
                        Text(lcManager.isLiveContainerInstalled
                            ? "Apps live only inside EmPoster — tap Run and choose LiveContainer to launch them. Nothing is installed on your device."
                            : "Apps live only inside EmPoster — tap Run and choose LiveContainer (or any installer) from the share sheet to launch them. Nothing is installed on your device.")
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    Haptic.shared.play(.light)
                    showImporter = true
                }) {
                    Image(systemName: "plus")
                }
            }
        }
        .onAppear {
            lcManager.refresh()
        }
    }

    private var emptyState: some View {
        ScrollView {
            VStack(spacing: 16) {
                Image(systemName: "app.badge")
                    .font(.system(size: 56))
                    .foregroundStyle(.tint)

                Text("No apps installed")
                    .font(.title3)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)

                Text("Import an .ipa to install it into EmPoster's container — it will never be installed on your iDevice. Tap Run afterwards to launch it via LiveContainer.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button(action: {
                    Haptic.shared.play(.light)
                    showImporter = true
                }) {
                    Text("Import IPA")
                        .fontWeight(.semibold)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(Color.blue))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)

                if lcManager.isLiveContainerInstalled {
                    Button(action: {
                        Haptic.shared.play(.light)
                        lcManager.openLiveContainer()
                    }) {
                        Text("Open LiveContainer")
                            .fontWeight(.semibold)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(Capsule().fill(Color(uiColor: .secondarySystemBackground)))
                            .foregroundStyle(Color(uiColor: .label))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(32)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Locked (non-Pro)

    private var lockedProSection: some View {
        VStack(spacing: 16) {
            Image(systemName: "crown.fill")
                .font(.system(size: 56))
                .foregroundStyle(.yellow)

            Text("Apps & Containers are Pro")
                .font(.title3)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)

            Text("Install apps into EmPoster's container and run them without installing them on your iDevice — with EmPoster Pro.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button(action: {
                Haptic.shared.play(.light)
                showSubscriptionSheet = true
            }) {
                Text("Unlock with Pro")
                    .fontWeight(.semibold)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(Color.yellow))
                    .foregroundStyle(.black)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .padding(32)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Actions

    private func run(_ app: InstalledApp) {
        Haptic.shared.play(.light)
        Task {
            do {
                let ipa = try await lcManager.exportIPA(for: app)
                shareItems = ShareItems(items: [ipa])
            } catch {
                Haptic.shared.notify(.error)
                UIApplication.shared.alert(title: "Could not prepare app", body: error.localizedDescription)
            }
        }
    }

    private func importRealData(_ app: InstalledApp) {
        guard BadQuery.isAvailable else {
            UIApplication.shared.alert(
                title: "Not available",
                body: "This requires bad_query (iOS 26/27) and the app to be installed on the device."
            )
            return
        }
        UIApplication.shared.alert(
            title: "Importing data…",
            body: "Copying \(app.name)'s container data via bad_query…",
            animated: false,
            withButton: false
        )
        Task {
            do {
                let count = try await lcManager.importDataFromInstalledApp(app)
                UIApplication.shared.dismissAlert(animated: true)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    Haptic.shared.notify(.success)
                    UIApplication.shared.alert(
                        title: "Data imported",
                        body: "Copied \(count) item(s) into \(app.name)'s data container."
                    )
                }
            } catch {
                UIApplication.shared.dismissAlert(animated: true)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    Haptic.shared.notify(.error)
                    UIApplication.shared.alert(title: "Import failed", body: error.localizedDescription)
                }
            }
        }
    }

    private func resetData(_ app: InstalledApp) {
        UIApplication.shared.confirmAlert(
            title: "Reset \(app.name)'s data?",
            body: "Clears the app's data container inside EmPoster. The app bundle stays.",
            onOK: {
                Task {
                    do {
                        try await self.lcManager.resetData(app)
                        Haptic.shared.notify(.success)
                        UIApplication.shared.alert(title: "Data reset", body: "\(app.name)'s container was cleared.")
                    } catch {
                        Haptic.shared.notify(.error)
                        UIApplication.shared.alert(title: "Reset failed", body: error.localizedDescription)
                    }
                }
            },
            noCancel: false
        )
    }

    private func confirmUninstall(_ app: InstalledApp) {
        UIApplication.shared.confirmAlert(
            title: "Uninstall \(app.name)?",
            body: "Removes the app bundle and its data container from EmPoster. Your device is not affected.",
            onOK: {
                Task {
                    do {
                        try await self.lcManager.uninstall(app)
                        Haptic.shared.notify(.success)
                        UIApplication.shared.alert(title: "Uninstalled", body: "\(app.name) was removed from EmPoster's container.")
                    } catch {
                        Haptic.shared.notify(.error)
                        UIApplication.shared.alert(title: "Uninstall failed", body: error.localizedDescription)
                    }
                }
            },
            noCancel: false
        )
    }

    private func uninstallApps(at offsets: IndexSet) {
        for index in offsets {
            confirmUninstall(lcManager.apps[index])
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls) where !urls.isEmpty:
            install(urls)
        case .failure(let error):
            Haptic.shared.notify(.error)
            UIApplication.shared.alert(body: error.localizedDescription)
        default:
            break
        }
    }

    private func install(_ urls: [URL]) {
        UIApplication.shared.alert(
            title: "Installing…",
            body: "Extracting app bundles…",
            animated: false,
            withButton: false
        )
        Task {
            var installed = 0
            var firstError: Error?
            for url in urls {
                do {
                    try await self.lcManager.install(from: url)
                    installed += 1
                } catch {
                    if firstError == nil { firstError = error }
                }
            }
            UIApplication.shared.dismissAlert(animated: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                if installed > 0 {
                    Haptic.shared.notify(.success)
                    UIApplication.shared.alert(
                        title: "Installed \(installed) app\(installed == 1 ? "" : "s")",
                        body: "Stored in EmPoster's container — nothing was installed on your device. Tap Run to launch via LiveContainer."
                    )
                } else {
                    Haptic.shared.notify(.error)
                    UIApplication.shared.alert(title: "Install failed", body: firstError?.localizedDescription ?? "Unknown error")
                }
            }
        }
    }

    @ViewBuilder
    private func contextMenu(for app: InstalledApp) -> some View {
        Button {
            run(app)
        } label: {
            Label("Run (Share to LiveContainer)", systemImage: "play.circle")
        }
        Button {
            importRealData(app)
        } label: {
            Label("Import Data from Installed App", systemImage: "arrow.down.circle")
        }
        Button {
            resetData(app)
        } label: {
            Label("Reset Data Container", systemImage: "arrow.counterclockwise.circle")
        }
        Button(role: .destructive) {
            confirmUninstall(app)
        } label: {
            Label("Uninstall", systemImage: "trash")
        }
    }
}

// MARK: - Row

struct AppRow: View {
    let app: InstalledApp
    let onRun: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if let icon = LiveContainerManager.shared.icon(for: app) {
                Image(uiImage: icon)
                    .resizable()
                    .frame(width: 48, height: 48)
                    .cornerRadius(10)
            } else {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(uiColor: .tertiarySystemFill))
                    .frame(width: 48, height: 48)
                    .overlay {
                        Image(systemName: "app.fill")
                            .foregroundStyle(.secondary)
                    }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(app.name)
                    .font(.headline)
                    .lineLimit(1)
                Text("\(app.bundleID) · v\(app.version)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(ByteCountFormatter.string(fromByteCount: app.size, countStyle: .file))
                    .font(.caption2)
                    .foregroundStyle(Color(uiColor: .tertiaryLabel))
            }

            Spacer()

            Button(action: onRun) {
                Image(systemName: "play.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.blue)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Run \(app.name)")
        }
        .padding(.vertical, 2)
    }
}