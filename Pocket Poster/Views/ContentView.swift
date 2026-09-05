//
//  ContentView.swift
//  EmPoster
//
//  Created by lemin on 5/31/25.
//

import SwiftUI
import UniformTypeIdentifiers

extension UIDocumentPickerViewController {
    @objc func fix_init(forOpeningContentTypes contentTypes: [UTType], asCopy: Bool) -> UIDocumentPickerViewController {
        return fix_init(forOpeningContentTypes: contentTypes, asCopy: true)
    }
}

struct ContentView: View {
    @ObservedObject private var patreonManager = PatreonManager.shared

    private let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
    
    var body: some View {
        NavigationStack {
            List {
                Section {} header: {
                    Label("Version \(Bundle.main.releaseVersionNumber ?? "UNKNOWN") (\(Int(buildNumber) != 0 ? "Beta \(buildNumber)" : NSLocalizedString("Release", comment:"")))", systemImage: "info.circle.fill")
                        .font(.caption)
                }
                
                // MARK: Account
                Section {
                    if patreonManager.isPro {
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.title2)
                                .foregroundStyle(.green)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("EmPoster Pro is Active")
                                    .font(.headline)
                                Text([
                                    patreonManager.memberName,
                                    patreonManager.tier
                                ].compactMap { $0 }.joined(separator: " · "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if patreonManager.isUltra {
                                    Text("Ultra Member")
                                        .font(.caption2)
                                        .foregroundStyle(.yellow)
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
                        NavigationLink(destination: {
                            SignInView()
                        }) {
                            HStack(spacing: 12) {
                                Image(systemName: "person.crop.circle.badge.checkmark")
                                    .font(.title2)
                                    .foregroundStyle(.blue)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Sign In / Subscribe")
                                        .font(.headline)
                                    Text("Google or Patreon — unlock Pro and submit wallpapers.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                        }
                    }
                } header: {
                    Label("Account", systemImage: "person.crop.circle")
                }

                // MARK: Device
                Section {
                    LabeledContent("Device Name", value: UIDevice.current.name)
                    LabeledContent("Device Model", value: machineName())
                    LabeledContent("Software Version", value: UIDevice.current.systemVersion)
                } header: {
                    Label("Device", systemImage: "iphone")
                }
            }
            .navigationTitle("EmPoster")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing, content: {
                    HStack {
                        NavigationLink(destination: {
                            SettingsView()
                        }, label: {
                            Image(systemName: "gear")
                        })
                    }
                })
            }
        }
    }
    
    init() {
        // Fix file picker
        let fixMethod = class_getInstanceMethod(UIDocumentPickerViewController.self, #selector(UIDocumentPickerViewController.fix_init(forOpeningContentTypes:asCopy:)))!
        let origMethod = class_getInstanceMethod(UIDocumentPickerViewController.self, #selector(UIDocumentPickerViewController.init(forOpeningContentTypes:asCopy:)))!
        method_exchangeImplementations(origMethod, fixMethod)
    }
}