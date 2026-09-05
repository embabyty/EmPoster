//
//  TendiesView.swift
//  EmPoster
//
//  Created by lemin on 9/5/25.
//

import SwiftUI
import UniformTypeIdentifiers

struct TendiesView: View {
    // Prefs
    @AppStorage("pbHash") var pbHash: String = ""
    
    @ObservedObject var pbManager = PosterBoardManager.shared
    
    @State var showTendiesImporter: Bool = false
    @State var hideResetHelp: Bool = true
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button(action: {
                        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                        showTendiesImporter.toggle()
                    }) {
                        Label("Select Tendies", systemImage: "document.circle")
                    }
                    .buttonStyle(TintedButton(color: .green, fullwidth: true))
                }
                .listRowInsets(EdgeInsets())
                .padding(7)
                
                if !pbManager.selectedTendies.isEmpty {
                    Section {
                        ForEach(pbManager.selectedTendies, id: \.self) { tendie in
                            Text(tendie.deletingPathExtension().lastPathComponent)
                        }
                        .onDelete(perform: delete)
                    } header: {
                        Label("Selected Tendies", systemImage: "document")
                    }
                }
                
                Section {
                    if pbHash == "" && !SymHandler.prefersBadQuery {
                        Text("Enter your PosterBoard app hash in Settings.")
                    } else {
                        VStack {
                            if pbHash == "" && SymHandler.prefersBadQuery {
                                Text("No hash set — will auto-detect via bad_query on Apply.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if !pbManager.selectedTendies.isEmpty || !pbManager.videos.isEmpty {
                                Button(action: {
                                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                                    UIApplication.shared.alert(title: NSLocalizedString("Applying Wallpapers...", comment: ""), body: NSLocalizedString("Please wait", comment: ""), animated: false, withButton: false)

                                    DispatchQueue.global(qos: .userInitiated).async {
                                        do {
                                            var hash = pbHash
                                            if hash.isEmpty {
                                                UIApplication.shared.change(title: NSLocalizedString("Applying Wallpapers...", comment: ""), body: "Detecting PosterBoard container…")
                                                hash = try BadQuery.findPosterBoardHash()
                                                DispatchQueue.main.async { pbHash = hash }
                                            }
                                            try pbManager.applyTendies(appHash: hash)
                                            SymHandler.cleanup() // just to be extra sure
                                            try? FileManager.default.removeItem(at: pbManager.getTendiesStoreURL())
                                            
                                            DispatchQueue.main.async {
                                                pbManager.selectedTendies.removeAll()
                                                pbManager.videos.removeAll()
                                                Haptic.shared.notify(.success)
                                                // Instant Mond-style respring (no alert delay)
                                                RespringHelper.respring()
                                            }
                                        } catch CocoaError.fileWriteUnknown {
                                            presentError(ApplyError.wrongAppHash)
                                        } catch CocoaError.fileWriteFileExists {
                                            presentError(ApplyError.collectionsNeedsReset)
                                        } catch {
                                            print(error.localizedDescription)
                                            presentError(ApplyError.unexpected(info: error.localizedDescription))
                                        }
                                    }
                                }) {
                                    Label("Apply", systemImage: "checkmark.circle")
                                }
                                .buttonStyle(TintedButton(color: .blue, fullwidth: true))
                            }
                            Button(action: {
                                UIApplication.shared.confirmAlert(
                                    title: NSLocalizedString("Reset Collections", comment: ""),
                                    body: SymHandler.prefersBadQuery
                                        ? "This will wipe custom PosterBoard descriptors via bad_query, then respring."
                                        : NSLocalizedString("Do you want to reset collections?", comment: ""),
                                    onOK: {
                                        UIApplication.shared.alert(
                                            title: "Resetting…",
                                            body: "Please wait",
                                            animated: true,
                                            withButton: false
                                        )
                                        DispatchQueue.global(qos: .userInitiated).async {
                                            do {
                                                var hash = pbHash
                                                if hash.isEmpty && SymHandler.prefersBadQuery {
                                                    hash = try BadQuery.findPosterBoardHash()
                                                    DispatchQueue.main.async { pbHash = hash }
                                                }
                                                guard !hash.isEmpty else {
                                                    throw ApplyError.wrongAppHash
                                                }
                                                try pbManager.resetCollections(appHash: hash)
                                                DispatchQueue.main.async {
                                                    Haptic.shared.notify(.success)
                                                    // Instant Mond-style respring
                                                    RespringHelper.respring()
                                                }
                                            } catch {
                                                presentError(ApplyError.unexpected(info: error.localizedDescription))
                                            }
                                        }
                                    },
                                    noCancel: false
                                )
                            }) {
                                Label("Reset Collections", systemImage: "arrow.clockwise.circle")
                            }
                            .buttonStyle(TintedButton(color: .red, fullwidth: true))
                        }
                        .listRowInsets(EdgeInsets())
                        .padding(7)
                    }
                } header: {
                    Label("Actions", systemImage: "hammer")
                }
            }
            .navigationTitle("Tendies")
        }
        .fileImporter(isPresented: $showTendiesImporter, allowedContentTypes: [UTType(filenameExtension: "tendies", conformingTo: .data)!], allowsMultipleSelection: true, onCompletion: { result in
            switch result {
            case .success(let url):
                if pbManager.selectedTendies.count + url.count > PosterBoardManager.MaxTendies {
                    UIApplication.shared.alert(title: NSLocalizedString("Max Tendies Reached", comment: ""), body: String(format: NSLocalizedString("You can only apply %@ descriptors.", comment: ""), "\(PosterBoardManager.MaxTendies)"))
                } else {
                    pbManager.selectedTendies.append(contentsOf: url)
                }
            case .failure(let error):
                Haptic.shared.notify(.error)
                UIApplication.shared.alert(body: error.localizedDescription)
            }
        })
        .overlay {
            OnBoardingView(cards: resetCollectionsInfo, isFinished: $hideResetHelp)
                .opacity(hideResetHelp ? 0.0 : 1.0)
                .transition(.opacity)
                .animation(.easeOut(duration: 0.5), value: hideResetHelp)
        }
    }
    
    func delete(at offsets: IndexSet) {
        pbManager.selectedTendies.remove(atOffsets: offsets)
    }
    
    func presentError(_ error: ApplyError) {
        SymHandler.cleanup()
        DispatchQueue.main.async {
            Haptic.shared.notify(.error)
            // alert() dismisses any buttonless progress sheet first, always with OK
            UIApplication.shared.alert(body: error.localizedDescription, withButton: true)
        }
    }
}