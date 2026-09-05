//
//  RootView.swift
//  EmPoster
//
//  Created by lemin on 6/11/25.
//

import SwiftUI

struct RootView: View {
    @ObservedObject private var patreonManager = PatreonManager.shared

    var body: some View {
        TabView {
            ContentView()
                .tabItem {
                    Label("Home", systemImage: "house")
                }
            TendiesView()
                .tabItem {
                    Label("Tendies", systemImage: "rectangle.stack")
                }
            CreateView()
                .tabItem {
                    Label("Create", systemImage: "square.and.pencil")
                }
            if patreonManager.isPro {
                MobileGestaltView()
                    .tabItem {
                        Label("MGA", systemImage: "cpu")
                    }
            }
            if CarPlayManager.supportsCarPlay() {
                CarPlayView()
                    .tabItem {
                        Label("CarPlay", systemImage: "car")
                    }
            }
            ExploreView()
                .tabItem {
                    Label("Explore", systemImage: "safari")
                }
        }
    }
}
