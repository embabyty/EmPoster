//
//  DaemonsView.swift
//  EmPoster
//
//  Nugget-style Daemons tweak menu. Each toggle disables the matching daemons
//  by writing them into /var/db/com.apple.xpc.launchd/disabled.plist through
//  the bad_query sandbox escape — no PC and no BookRestore needed.
//

import SwiftUI

struct DaemonsView: View {
    @ObservedObject private var manager = DaemonsManager.shared

    @State private var isApplying = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("Modify Daemons", isOn: $manager.isModifyingDaemons)
                } footer: {
                    Text("Allows writing the selected daemon changes to /var/db/com.apple.xpc.launchd/disabled.plist using the bad_query sandbox escape. A restart is required for the changes to take effect.")
                }

                ForEach(DaemonGroup.all) { group in
                    Section {
                        ForEach(group.toggles) { toggle in
                            daemonRow(toggle)
                        }
                    } header: {
                        Label(group.title, systemImage: group.icon)
                    }
                    .disabled(!manager.isModifyingDaemons)
                    .opacity(manager.isModifyingDaemons ? 1 : 0.5)
                }
            }
            .navigationTitle("Daemons")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: apply) {
                        if isApplying {
                            ProgressView()
                        } else {
                            Text("Apply")
                        }
                    }
                    .disabled(isApplying)
                }
            }
        }
    }

    // MARK: - Row

    private func daemonRow(_ toggle: DaemonToggle) -> some View {
        Toggle(isOn: Binding(
            get: {
                toggle.clearsScreenTimeFile
                    ? manager.clearScreenTimeFile
                    : manager.enabledToggles.contains(toggle.id)
            },
            set: { newValue in
                if toggle.clearsScreenTimeFile {
                    manager.clearScreenTimeFile = newValue
                } else {
                    manager.setToggle(toggle, enabled: newValue)
                }
            }
        )) {
            HStack(spacing: 10) {
                Text(toggle.title)
                    .foregroundStyle(Color(uiColor: .label))
                Spacer()
                if let info = toggle.info {
                    Button {
                        UIApplication.shared.alert(title: "Info", body: info)
                    } label: {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Apply

    private func apply() {
        guard manager.isModifyingDaemons || manager.clearScreenTimeFile else {
            UIApplication.shared.alert(title: "Nothing to apply", body: "Turn on \"Modify Daemons\" or select a daemon to disable first.")
            return
        }

        isApplying = true
        UIApplication.shared.alert(
            title: "Applying Daemons…",
            body: "Writing daemon preferences via bad_query…",
            animated: false,
            withButton: false
        )

        Task {
            do {
                try await manager.apply()
                Haptic.shared.notify(.success)
                UIApplication.shared.dismissAlert(animated: true)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    isApplying = false
                    UIApplication.shared.alert(
                        title: "Daemons updated",
                        body: "Restart your device for the changes to take effect."
                    )
                }
            } catch {
                Haptic.shared.notify(.error)
                UIApplication.shared.dismissAlert(animated: true)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    isApplying = false
                    UIApplication.shared.alert(title: "Failed to apply Daemons", body: error.localizedDescription)
                }
            }
        }
    }
}