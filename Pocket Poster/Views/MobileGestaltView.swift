//
//  MobileGestaltView.swift
//  Pocket Poster
//
//  MobileGestalt (MGA) tweak UI, ported from rooootdev/mond's GestaltView.
//  Replaces the PartyUI components (PlainToggle / PlainAlert / Alertinator)
//  with native SwiftUI equivalents.
//

import SwiftUI

struct MobileGestaltView: View {
    @ObservedObject private var manager = MobileGestaltManager.shared

    @State private var selectedSubtype = "og"
    @State private var enableDeviceName = false
    @State private var deviceName = ""
    @State private var productType = ""

    var selectedSubtypeValue: Int {
        switch selectedSubtype {
        case "og":
            return manager.originalSubtype
        case "no_dynamic_island":
            return 0
        case "14p":
            return 2436
        case "14pm":
            return 2796
        case "15pm":
            return 2976
        case "16p":
            return 2622
        case "16pm":
            return 2868
        case "air":
            return 2736
        case "x":
            return 2436
        default:
            return 0
        }
    }

    private var subtypeToSelection: [Int: String] {
        [
            0: "no_dynamic_island",
            2436: "14p",
            2796: "14pm",
            2976: "15pm",
            2622: "16p",
            2868: "16pm",
            2736: "air"
        ]
    }

    var body: some View {
        List {
            if !manager.isValid || manager.isEmpty {
                Section {
                    if manager.isEmpty {
                        MGWarning(
                            title: "Do not reboot!",
                            icon: "exclamationmark.triangle.fill",
                            text: "Your MobileGestalt.plist seems to be empty.",
                            color: .yellow
                        )
                    }

                    if !manager.isValid {
                        MGWarning(
                            title: "Do not reboot!",
                            icon: "exclamationmark.triangle.fill",
                            text: "Your MobileGestalt.plist seems to be invalid.",
                            color: .yellow
                        )
                    }
                } header: {
                    Label("Warning", systemImage: "exclamationmark.triangle")
                } footer: {
                    Text("Rebooting now might cause a bootloop. Try pressing 'Revert Tweaks'. If the warnings don't go away after that, you're fucked.")
                }
            }

            if manager.isLoading {
                Section {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Loading MobileGestalt…")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                Button {
                    mgApply()
                } label: {
                    Text("Apply Tweaks")
                }
                .disabled(!manager.isLoaded)

                Button {
                    mgRevert()
                } label: {
                    Text("Revert Tweaks")
                }
            } footer: {
                Text("**WARNING:** These tweaks have the capability to break features on your device or softbrick it if misused!")
            }

            if manager.isLoaded {

                Section {
                    Picker(selection: $selectedSubtype) {
                        Text("Original (\(manager.originalSubtype))").tag("og")

                        if isDeviceGood() {
                            Text("Disable Dynamic Island").tag("no_dynamic_island")
                        }

                        Text("iPhone 14 Pro").tag("14p")
                        Text("iPhone 14 Pro Max").tag("14pm")
                        Text("iPhone 15 Pro Max").tag("15pm")

                        if doubleSystemVersion() >= 18.0 {
                            Text("iPhone 16 Pro").tag("16p")
                            Text("iPhone 16 Pro Max").tag("16pm")
                        }

                        if doubleSystemVersion() >= 26.0 {
                            Text("iPhone Air").tag("air")
                        }

                        if hasHomeButton() {
                            Text("iPhone X Gestures").tag("x")
                        }
                    } label: {
                        Text("Subtype")
                    }

                    Toggle("Custom Device Name", isOn: $enableDeviceName)

                    if enableDeviceName {
                        TextField("Device Name", text: $deviceName)
                    }
                } header: {
                    Label("Device Artwork", systemImage: "paintbrush.pointed")
                }

                // basic tweak toggles
                Section {
                    mgToggle(text: "Dynamic Island", isOn: keyBinding(["YlEtTtHlNesRBMal1CqRaA"], type: Int.self), minSupportedVersion: 19.0)
                    mgToggle(text: "Always On Display", isOn: keyBinding(["j8/Omm6s1lsmTDFsXjsBfA", "2OOJf1VhaM7NxfRok3HbWQ"], type: Int.self), minSupportedVersion: 18.0)
                    mgToggle(text: "AOD Vibrancy", isOn: keyBinding(["ykpu7qyhqFweVMKtxNylWA"], type: Int.self), minSupportedVersion: 18.0)
                    mgToggle(text: "Charge Limit", isOn: keyBinding(["37NVydb//GP/GrhuTN+exg"], type: Int.self), minSupportedVersion: 17.0)
                    mgToggle(text: "Boot Chime", isOn: keyBinding(["QHxt+hGLaBPbQJbXiUJX3w"], type: Int.self))
                    mgToggle(text: "Liquid Glass LPM", isOn: keyBinding(["SAGvsp6O6kAQ4fEfDJpC4Q"], type: Int.self), minSupportedVersion: 19.0)
                } header: {
                    Label("Software-Oriented Features", systemImage: "gearshape")
                }

                Section {
                    mgToggle(text: "Camera Control", isOn: keyBinding(["CwvKxM2cEogD3p+HYgaW0Q", "oOV1jhJbdV3AddkcCg0AEA"], type: Int.self), minSupportedVersion: 18.0)
                    mgToggle(text: "Action Button", isOn: keyBinding(["cT44WE1EohiwRzhsZ8xEsw"], type: Int.self), minSupportedVersion: 17.0)
                    mgToggle(text: "Crash Detection", isOn: keyBinding(["HCzWusHQwZDea6nNhaKndw"], type: Int.self))
                    if hasHomeButton() {
                        mgToggle(text: "Enable Tap to Wake", isOn: keyBinding(["yZf3GTRMGTuwSV/lD7Cagw"], type: Int.self))
                    }
                    mgToggle(text: "Pulse Width Modulation", isOn: keyBinding(["6IejgN+1Fmu5/QrZFOIeNw"], type: Int.self), minSupportedVersion: 19.0)
                } header: {
                    Label("Hardware-Oriented Features", systemImage: "iphone")
                }

                Section {
                    mgToggle(text: "Security Research Device UI", isOn: keyBinding(["XYlJKKkj2hztRP1NWWnhlw"], type: Int.self), minSupportedVersion: 26.0)

                    mgToggle(
                        text: "Disable Region Restrictions",
                        isOn: regionRestrictBinding(),
                        infoMessage: "This tweak may be broken or have no effect on some iOS versions or devices."
                    )

                    mgToggle(
                        text: "Apple Intelligence",
                        isOn: appleIntelligenceBinding(),
                        infoMessage: "How to use this tweak:\n1. Spoof to the model next to the first one supported by Apple Intelligence.\n2. Spoof back to your model.\n3. Spoof to your final model and you should see the Apple Intelligence icon in Settings.\n4. Connect iPhone to power and leave the Settings > Storage tab open for ~1 hour.\n\nNOTE: Do not spoof back.",
                        minSupportedVersion: 18.1
                    )

                    HStack(spacing: 10) {
                        Picker("Spoofing", selection: $productType) {
                            Text("Default").tag(machineName())
                            if UIDevice.current.userInterfaceIdiom == .pad {
                                if doubleSystemVersion() >= 17.4 {
                                    Text("iPad Pro 11-inch (M4)").tag("iPad16,3")
                                    Text("iPad Pro 11-inch (M4, Cellular)").tag("iPad16,4")
                                }
                                Text("iPad Pro 11-inch (4th Gen)").tag("iPad14,3")
                                Text("iPad Pro 11-inch (4th Gen, Cellular)").tag("iPad14,4")
                            } else {
                                Text("iPhone 15 Pro").tag("iPhone16,1")
                                Text("iPhone 15 Pro Max").tag("iPhone16,2")
                                if doubleSystemVersion() >= 18.0 {
                                    Text("iPhone 16").tag("iPhone17,3")
                                    Text("iPhone 16 Plus").tag("iPhone17,4")
                                    Text("iPhone 16 Pro").tag("iPhone17,1")
                                    Text("iPhone 16 Pro Max").tag("iPhone17,2")
                                }
                                if doubleSystemVersion() >= 19.0 {
                                    Text("iPhone 17").tag("iPhone18,3")
                                    Text("iPhone 17 Pro").tag("iPhone18,1")
                                    Text("iPhone 17 Pro Max").tag("iPhone18,2")
                                    Text("iPhone Air").tag("iPhone18,4")
                                }
                            }
                        }

                        Button {
                            showInfoMessage("Only spoof your device model if you want to download Apple Intelligence. This may break Face ID. If you decide to unspoof and want to keep Apple Intelligence, do NOT re-enter the Apple Intelligence & Siri menu in Settings.")
                        } label: {
                            Image(systemName: "info.circle")
                                .frame(width: 24, height: 22)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Label("Eligibility", systemImage: "checklist")
                }

                Section {
                    mgToggle(
                        text: "Allow Installing iPadOS Apps",
                        isOn: keyBinding(["9MZ5AdH43csAUajl/dU+IQ"], type: [Int].self, defaultValue: [1], onValue: [1, 2])
                    )
                    mgToggle(text: "Apple Pencil Settings", isOn: keyBinding(["yhHcB0iH0d1XzPO/CFd3ow"], type: Int.self))

                    if UIDevice.current.userInterfaceIdiom == .pad {
                        mgToggle(text: "Stage Manager", isOn: keyBinding(["qeaj75wk3HF4DwQ8qbIi7g"], type: Int.self))
                    }

                    mgToggle(
                        text: "iPadOS UI",
                        isOn: trollpadBinding(),
                        infoMessage: "This is a very dangerous tweak to use! If you use an alphanumeric passcode, DO NOT USE THIS TWEAK AT ALL! Please do not turn off \"Show Dock In Stage Manager\" or your device will BOOTLOOP when rotating to landscape! Some users have also reported that enabling the iPadOS UI and then tapping Stage Manager can cause the device to enter Recovery Mode, even when the UI itself appears unchanged. The Settings search bar may move to the top before this happens. With these three things in mind, you may experience general instability, or other major issues such as app data randomly disappearing. But I guess some funny multitasking features that still make the device relatively unusable are cool? Whatever dude, I'm not here to tell you how to use your own device.",
                        warningOnEnable: "This is a very dangerous tweak to use! If you use an alphanumeric passcode, DO NOT USE THIS TWEAK AT ALL! Please do not turn off \"Show Dock In Stage Manager\" or your device will BOOTLOOP when rotating to landscape! With these two things in mind, you may experience general instability, or other major issues such as app data randomly disappearing. I'm honestly not too certain why you'd want to use this tweak anyways, it's not like your device is gonna be all that usable (due to apps scaling weirdly) when it's enabled."
                    )
                    .disabled(manager.cacheExtra?["+3Uf0Pm5F8Xy7Onyvko0vA"] as? String != "iPhone")
                } header: {
                    Label("iPadOS Features", systemImage: "ipad")
                }

                Section {
                    mgToggle(text: "Internal Storage", isOn: keyBinding(["LBJfwOEzExRxzlAnSuI7eg"], type: Int.self))
                    mgToggle(text: "Internal Features", isOn: internalBinding())
                    mgToggle(text: "Metal HUD in All Apps", isOn: keyBinding(["EqrsVvjcYDdxHBiQmGhAWw"], type: Int.self))
                } header: {
                    Label("Internal", systemImage: "ant")
                }
            }
        }
        .navigationTitle("MobileGestalt")
        .onAppear {
            manager.load()

            // Sync local state from the loaded dictionary (if already loaded)
            if manager.isLoaded {
                let cacheExtra = manager.cacheExtra
                let artwork = cacheExtra?["oPeik/9e8lQWMszEjbPzng"] as? NSMutableDictionary
                let subtype = artwork?["ArtworkDeviceSubType"] as? Int
                let name = artwork?["ArtworkDeviceProductDescription"] as? String

                selectedSubtype = subtype.flatMap { subtypeToSelection[$0] } ?? "og"
                deviceName = name ?? manager.originalDeviceName
                enableDeviceName = name != nil && name != manager.originalDeviceName
                productType = cacheExtra?["h9jDsbgj7xIVeIQ8S3/X3Q"] as? String ?? machineName()
            }
        }
        .onReceive(manager.$dictionary) { _ in
            if manager.isLoaded {
                let cacheExtra = manager.cacheExtra
                let artwork = cacheExtra?["oPeik/9e8lQWMszEjbPzng"] as? NSMutableDictionary
                let subtype = artwork?["ArtworkDeviceSubType"] as? Int
                let name = artwork?["ArtworkDeviceProductDescription"] as? String

                selectedSubtype = subtype.flatMap { subtypeToSelection[$0] } ?? "og"
                deviceName = name ?? manager.originalDeviceName
                enableDeviceName = name != nil && name != manager.originalDeviceName
                productType = cacheExtra?["h9jDsbgj7xIVeIQ8S3/X3Q"] as? String ?? machineName()
            }
        }
        .alert("MobileGestalt Error", isPresented: Binding(
            get: { manager.lastError != nil },
            set: { if !$0 { manager.lastError = nil } }
        )) {
            Button("OK", role: .cancel) { manager.lastError = nil }
        } message: {
            Text(manager.lastError ?? "")
        }
    }

    // MARK: - Apply / Revert

    private func mgApply() {
        do {
            let cacheExtra = manager.cacheExtra ?? NSMutableDictionary()
            if !productType.isEmpty {
                cacheExtra["h9jDsbgj7xIVeIQ8S3/X3Q"] = productType
            }

            let artwork = cacheExtra["oPeik/9e8lQWMszEjbPzng"] as? NSMutableDictionary ?? NSMutableDictionary()
            artwork["ArtworkDeviceSubType"] = selectedSubtypeValue
            if enableDeviceName {
                artwork["ArtworkDeviceProductDescription"] = deviceName
            }

            try manager.apply()
            deviceName = ""
            enableDeviceName = false

            UIApplication.shared.confirmAlert(
                title: "Successfully applied Gestalt tweaks!",
                body: "Respring your device for changes to take effect. Note that some tweaks may require a reboot for them to apply properly.",
                confirmTitle: "Respring",
                onOK: {
                    RespringHelper.respring()
                },
                noCancel: false
            )
        } catch {
            UIApplication.shared.alert(title: "Failed to apply MobileGestalt!", body: error.localizedDescription)
        }
    }

    private func mgRevert() {
        do {
            try manager.revert()
            UIApplication.shared.alert(title: "Successfully reverted Gestalt tweaks!", body: "Reboot your device for changes to take effect.")
        } catch {
            UIApplication.shared.alert(title: "Failed to revert MobileGestalt!", body: error.localizedDescription)
        }
    }

    // MARK: - Info

    private func showInfoMessage(_ message: String) {
        UIApplication.shared.alert(title: "Info", body: message)
    }

    // MARK: - Toggle Bindings (ported from mond)

    private func keyBinding<T: Equatable>(
        _ keys: [String],
        type: T.Type = Int.self,
        defaultValue: T? = 0,
        onValue: T? = 1
    ) -> Binding<Bool> {
        Binding(
            get: {
                guard let cacheExtra = manager.cacheExtra,
                      let onValue,
                      let value = cacheExtra[keys.first!] as? T else { return false }
                return value == onValue
            },
            set: { enabled in
                guard let cacheExtra = manager.cacheExtra else { return }
                for key in keys {
                    if enabled {
                        cacheExtra[key] = onValue
                    } else {
                        cacheExtra.removeObject(forKey: key)
                    }
                }
            }
        )
    }

    private func regionRestrictBinding() -> Binding<Bool> {
        Binding<Bool>(
            get: {
                guard let cacheExtra = manager.cacheExtra else { return false }
                return cacheExtra["h63QSdBCiT/z0WU6rdQv6Q"] as? String == "US" &&
                    cacheExtra["zHeENZu+wbg7PUprwNwBWg"] as? String == "LL/A"
            },
            set: { enabled in
                guard let cacheExtra = manager.cacheExtra else { return }
                if enabled {
                    UIApplication.shared.alert(title: "Warning!", body: "Please do not use this feature to bypass region restrictions that would equate to breaking regional laws (e.g. disabling the camera shutter sound). We will NOT be held responsible for enabling any illegal activities!")
                    cacheExtra["h63QSdBCiT/z0WU6rdQv6Q"] = "US"
                    cacheExtra["zHeENZu+wbg7PUprwNwBWg"] = "LL/A"
                } else {
                    cacheExtra.removeObject(forKey: "h63QSdBCiT/z0WU6rdQv6Q")
                    cacheExtra.removeObject(forKey: "zHeENZu+wbg7PUprwNwBWg")
                }
            }
        )
    }

    private func appleIntelligenceBinding() -> Binding<Bool> {
        let key = "A62OafQ85EJAiiqKn4agtg"

        return Binding<Bool>(
            get: {
                guard let cacheExtra = manager.cacheExtra else { return false }
                if let value = cacheExtra[key] as? Int {
                    return value == 1
                }
                return false
            },
            set: { enabled in
                guard let cacheExtra = manager.cacheExtra else { return }
                if enabled {
                    cacheExtra[key] = 1
                    UIApplication.shared.alert(
                        title: "Apple Intelligence Spoof",
                        body: "How to use this tweak:\n1. Spoof to the model next to the first one supported by Apple Intelligence.\n2. Spoof back to your model.\n3. Spoof to your final model and you should see the Apple Intelligence icon in Settings.\n4. Connect iPhone to power and leave the Settings > Storage tab open for ~1 hour.\n\nNOTE: Do not spoof back."
                    )
                } else {
                    cacheExtra.removeObject(forKey: key)
                }
            }
        )
    }

    private func internalBinding() -> Binding<Bool> {
        return Binding(
            get: {
                manager.cacheDataInt(for: "EqrsVvjcYDdxHBiQmGhAWw") == 1
            },
            set: { enabled in
                let keys = ["EqrsVvjcYDdxHBiQmGhAWw", "Oji6HRoPi7rH7HPdWVakuw", "LBJfwOEzExRxzlAnSuI7eg"]
                // Resolve every offset first so we never write a partial result.
                guard keys.allSatisfy({ manager.cacheDataOffset(for: $0) > 0 }) else {
                    UIApplication.shared.alert(title: "Not supported on this iOS!", body: "Could not resolve the required MobileGestalt offsets.")
                    return
                }
                let value = enabled ? 1 : 0
                for key in keys {
                    manager.setCacheDataInt(value, for: key)
                }
            }
        )
    }

    private func trollpadBinding() -> Binding<Bool> {
        let values: [String: Int] = [
            "mG0AnH/Vy1veoqoLRAIgTA": 1, // MedusaFloatingLiveAppCapability
            "UCG5MkVahJxG1YULbbd5Bg": 1, // MedusaOverlayAppCapability
            "ZYqko/XM5zD3XBfN5RmaXA": 1, // MedusaPinnedAppCapability
            "nVh/gwNpy7Jv1NOk00CMrw": 1, // MedusaPIPCapability
            "uKc7FPnEO++lVhHWHFlGbQ": 1, // ipad
        ]

        return Binding(
            get: {
                guard let cacheExtra = manager.cacheExtra else { return false }
                return values.allSatisfy { key, value in
                    (cacheExtra[key] as? Int) == value
                }
            },
            set: { enabled in
                guard let cacheExtra = manager.cacheExtra else { return }
                if enabled {
                    UIApplication.shared.alert(
                        title: "Warning!",
                        body: "This is a very dangerous tweak to use! If you use an alphanumeric passcode, DO NOT USE THIS TWEAK AT ALL! Please do not turn off \"Show Dock In Stage Manager\" or your device will BOOTLOOP when rotating to landscape! With these two things in mind, you may experience general instability, or other major issues such as app data randomly disappearing. I'm honestly not too certain why you'd want to use this tweak anyways, it's not like your device is gonna be all that usable (due to apps scaling weirdly) when it's enabled."
                    )
                }

                guard manager.setCacheDataInt(enabled ? 3 : 1, for: "mtrAoWJ3gsq+I90ZnQ0vQw") else {
                    UIApplication.shared.alert(title: "Not supported on this iOS!", body: "Could not resolve the required MobileGestalt offsets.")
                    return
                }

                if enabled {
                    for (key, value) in values {
                        cacheExtra[key] = value
                    }
                } else {
                    for key in values.keys {
                        cacheExtra.removeObject(forKey: key)
                    }
                }
            }
        )
    }

    // MARK: - Device Helpers

    private func isDeviceGood() -> Bool {
        let supported: [String] = ["iPhone15,2", "iPhone15,3", "iPhone15,4", "iPhone15,5", "iPhone16,1", "iPhone16,2", "iPhone17,3", "iPhone17,4", "iPhone17,1", "iPhone17,2", "iPhone18,3", "iPhone18,1", "iPhone18,2", "iPhone17,5"]

        if supported.contains(machineName()) && doubleSystemVersion() < 19.0 {
            return true
        }

        return false
    }

    // MARK: - Row Builder

    /// Toggle row with optional version gating, info button, and enable-warning alert.
    private func mgToggle(
        text: String,
        isOn: Binding<Bool>,
        infoMessage: String? = nil,
        minSupportedVersion: Double? = nil,
        warningOnEnable: String? = nil
    ) -> some View {
        let supported = minSupportedVersion.map { doubleSystemVersion() >= $0 } ?? true

        return Toggle(isOn: Binding(
            get: { isOn.wrappedValue },
            set: { newValue in
                if newValue, let warning = warningOnEnable {
                    UIApplication.shared.confirmAlert(
                        title: "Warning!",
                        body: warning,
                        confirmTitle: "Enable",
                        onOK: { isOn.wrappedValue = true },
                        noCancel: false
                    )
                } else {
                    isOn.wrappedValue = newValue
                }
            }
        )) {
            HStack(spacing: 10) {
                Text(text)
                    .foregroundStyle(Color(uiColor: .label))
                Spacer()
                if let infoMessage {
                    Button {
                        showInfoMessage(infoMessage)
                    } label: {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .disabled(!supported)
        .opacity(supported ? 1 : 0.5)
    }
}

// MARK: - Warning Box (PlainAlert equivalent)

private struct MGWarning: View {
    let title: String
    let icon: String
    let text: String
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(color)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(color)
                Text(text)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(color.opacity(0.15))
        )
    }
}