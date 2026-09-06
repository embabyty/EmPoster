//
//  CreateView.swift
//  EmPoster
//
//  Created by lemin on 9/5/25.
//
//  Submit a tendie wallpaper request. Submissions are NOT published —
//  they stay hidden until an admin/staff account approves them.
//

import SwiftUI
import UniformTypeIdentifiers

struct CreateView: View {
    @ObservedObject private var community = CommunityManager.shared
    @ObservedObject private var patreon = PatreonManager.shared

    @State private var showImporter = false
    @State private var storedFiles: [String] = []
    @State private var title = ""
    @State private var description = ""
    @State private var tagsText = ""
    @State private var showSubmittedAlert = false
    @State private var hasScreenRecorded = false

    var body: some View {
        NavigationStack {
            Form {
                // MARK: Screen Recording (required before importing)
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("You must screen record the tendie wallpaper before importing the Tendie file.")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("Open the tendie wallpaper on your device, swipe up to open Control Center, and start a screen recording. Let it record until the wallpaper is fully visible, then stop and import the Tendie file below.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Toggle("I've screen recorded the tendie wallpaper", isOn: $hasScreenRecorded)
                            .font(.subheadline)
                    }
                    .padding(.vertical, 2)
                } header: {
                    Label("Screen Recording Required", systemImage: "record.circle")
                } footer: {
                    Text(hasScreenRecorded
                         ? "Thanks! You can now import your Tendie file."
                         : "You can't import a Tendie file until you confirm you've screen recorded the wallpaper.")
                }

                // MARK: Tendies
                Section {
                    Button {
                        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                        showImporter.toggle()
                    } label: {
                        Label(storedFiles.isEmpty ? "Import Tendies" : "Import More Tendies", systemImage: "tray.and.arrow.down")
                    }
                    .disabled(!hasScreenRecorded)
                    if !storedFiles.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(storedFiles, id: \.self) { name in
                                    VStack(spacing: 4) {
                                        TendiePreviewImage(storedFileName: name)
                                            .frame(width: 63, height: 120)
                                            .cornerRadius(8)
                                        Text(name)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                            }
                        }
                    }
                } header: {
                    Label("Tendie Wallpaper", systemImage: "photo.on.rectangle.angled")
                }

                // MARK: Details
                Section {
                    TextField("Title", text: $title)
                    TextField("Description", text: $description, axis: .vertical)
                        .lineLimit(3...6)
                    TextField("Tags", text: $tagsText)
                        .textInputAutocapitalization(.never)
                } header: {
                    Label("Details", systemImage: "square.and.pencil")
                } footer: {
                    Text("Separate tags with commas. Your request won't appear in Explore until staff approves it.")
                }

                // MARK: Submit
                Section {
                    Button {
                        submit()
                    } label: {
                        Label("Done", systemImage: "paperplane.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(storedFiles.isEmpty || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } footer: {
                    if let name = patreon.memberName {
                        Text("Submitting as \(name)")
                    } else {
                        Text("Log in with Patreon in Home to attach your account to this wallpaper.")
                    }
                }

                // MARK: Moderation (admins only)
                if community.isAdmin && !community.pending.isEmpty {
                    Section {
                        ForEach(community.pending) { submission in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(submission.title)
                                    .font(.headline)
                                Text(submission.authorName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                HStack(spacing: 20) {
                                    Button {
                                        community.approve(submission)
                                    } label: {
                                        Label("Approve", systemImage: "checkmark.circle.fill")
                                            .foregroundStyle(.green)
                                    }
                                    Button {
                                        community.reject(submission)
                                    } label: {
                                        Label("Reject", systemImage: "xmark.circle.fill")
                                            .foregroundStyle(.red)
                                    }
                                }
                                .font(.subheadline)
                            }
                            .padding(.vertical, 2)
                        }
                    } header: {
                        Label("Pending Approval", systemImage: "clock.badge.questionmark")
                    } footer: {
                        Text("Approved requests show up in Explore for everyone. Rejected requests are removed.")
                    }
                }
            }
            .navigationTitle("Create")
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [UTType(filenameExtension: "tendies", conformingTo: .data)!], allowsMultipleSelection: true, onCompletion: { result in
                switch result {
                case .success(let urls):
                    for url in urls {
                        do {
                            let name = try community.storeTendie(from: url)
                            storedFiles.append(name)
                        } catch {
                            Haptic.shared.notify(.error)
                            UIApplication.shared.alert(body: error.localizedDescription)
                        }
                    }
                    Haptic.shared.notify(.success)
                case .failure(let error):
                    Haptic.shared.notify(.error)
                    UIApplication.shared.alert(body: error.localizedDescription)
                }
            })
            .alert("Submitted!", isPresented: $showSubmittedAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Your tendie request has been submitted for review. It will appear in Explore after a staff member approves it.")
            }
        }
    }

    private func submit() {
        let tags = tagsText
            .split(whereSeparator: { $0 == "," })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let submittedFiles = storedFiles
        let submittedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let submittedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)

        Task {
            await community.submit(
                title: submittedTitle,
                description: submittedDescription,
                tags: tags,
                tendieFiles: submittedFiles
            )

            storedFiles = []
            title = ""
            description = ""
            tagsText = ""
            hasScreenRecorded = false
            Haptic.shared.notify(.success)
            showSubmittedAlert = true
        }
    }
}