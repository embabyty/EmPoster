//
//  TendiePreviewImage.swift
//  EmPoster
//
//  Created by lemin on 9/5/25.
//
//  Best-effort preview thumbnail for a tendie wallpaper.
//  - `storagePath`: Firebase Storage path (online mode) — downloads via
//    a Storage download URL and renders with CachedAsyncImage.
//  - `storedFileName`: local file in the community store (offline mode) —
//    extracts the largest image from the tendie zip.
//

import SwiftUI
import UIKit
import CachedAsyncImage

struct TendiePreviewImage: View {
    var storedFileName: String?
    var storagePath: String?

    @State private var image: UIImage?
    @State private var previewURL: URL?

    var body: some View {
        Group {
            if let storagePath {
                if let previewURL {
                    CachedAsyncImage(url: previewURL, urlCache: .imageCache) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } placeholder: {
                        placeholder
                    }
                } else {
                    placeholder
                }
            } else if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                placeholder
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.gray.opacity(0.15))
        .task(id: storagePath) {
            guard let storagePath else { return }
            previewURL = try? await FirebaseManager.shared.downloadURL(forPath: storagePath)
        }
        .task(id: storedFileName) {
            guard let storedFileName else {
                image = nil
                return
            }
            let img = await Task.detached(priority: .utility) {
                CommunityPreviewStore.image(forStoredFile: storedFileName)
            }.value
            image = img
        }
    }

    private var placeholder: some View {
        Image(systemName: "photo.on.rectangle.angled")
            .font(.largeTitle)
            .foregroundStyle(.secondary)
    }
}