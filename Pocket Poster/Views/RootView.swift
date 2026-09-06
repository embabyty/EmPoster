//
//  RootView.swift
//  EmPoster
//
//  Created by lemin on 6/11/25.
//

import SwiftUI

struct RootView: View {
    @ObservedObject private var patreonManager = PatreonManager.shared

    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            ContentView(selectedTab: $selectedTab)
                .tabItem {
                    Label("Home", systemImage: "house")
                }
                .tag(0)
            ExploreView()
                .tabItem {
                    Label("Explore", systemImage: "safari")
                }
                .tag(1)
            CreateView()
                .tabItem {
                    Label("Create", systemImage: "square.and.pencil")
                }
                .tag(2)
            if patreonManager.isPro {
                MobileGestaltView()
                    .tabItem {
                        Label("MGA", systemImage: "cpu")
                    }
                    .tag(3)
            }
            if CarPlayManager.supportsCarPlay() {
                CarPlayView()
                    .tabItem {
                        Label("CarPlay", systemImage: "car")
                    }
                    .tag(4)
            }
            ProfileView()
                .tabItem {
                    Label("Profile", systemImage: "person.crop.circle")
                }
                .tag(5)
        }
    }
}