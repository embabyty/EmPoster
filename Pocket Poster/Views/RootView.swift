//
//  RootView.swift
//  EmPoster
//
//  Created by lemin on 6/11/25.
//

import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            ContentView()
                .tabItem {
                    Label("Home", systemImage: "house")
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
