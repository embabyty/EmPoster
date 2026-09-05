//
//  TendiePreviewImage.swift
//  EmPoster
//
//  Created by lemin on 9/5/25.
//
//  Best-effort preview thumbnail for a tendie wallpaper.
//  - `previewURL`: served by the proxy server (remote submissions) —
//    rendered with AsyncImage.
//  - `storedFileName`: local file in the community store (offline mode) —
//    extracts the largest image from the tendie zip.
//

import SwiftUI
import UIKit

struct TendiePreviewImage: View {
    var previewURL: URL?
    var storedFileName: String?

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let previewURL {
                AsyncImage(url: previewURL) { phase in
                    switch phase {
                    case .success(let loaded):
                        loaded
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    case .failure:
                        placeholder
                    case .empty:
                        ProgressView()
                    @unknown default:
                        placeholder
                    }
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