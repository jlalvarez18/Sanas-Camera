//
//  VideoLibraryView.swift
//  Sanas Camera
//
//  Created by Juan Alvarez on 10/22/25.
//

import SwiftUI
import SwiftData
import AVKit
import LucideIcons

struct GalleryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \VideoItem.timestamp, order: .reverse) private var videos: [VideoItem]
    
    @State private var selectedVideo: IdentifiedURL?

    var body: some View {
        Group {
            if videos.isEmpty {
                Text("No Videos Recorded")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    PeekingScrollView(videos, contentMargin: 24, spacing: 16) { index, video in
                        VideoCard(video: video) { video in
                            if let url = video.localVideoURL ?? video.remoteVideoURL {
                                selectedVideo = IdentifiedURL(url: url)
                            } else {
                                print("GalleryView: Invalid video.filePath: \(video.filePath)")
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                }
                .sheet(item: $selectedVideo) { item in
                    PlayerSheet(url: item.url)
                        .ignoresSafeArea()
                }
            }
        }
        .navigationTitle("Gallery")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Simple AVPlayer Sheet

private struct PlayerSheet: View, Identifiable {
    let id = UUID()
    let url: URL
    
    let player: AVPlayer
    
    init(url: URL) {
        self.url = url
        self.player = AVPlayer(url: url)
    }
    
    var body: some View {
        VideoPlayer(player: player)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    player.play()
                }
            }
    }
}

private struct IdentifiedURL: Identifiable, Equatable {
    let id = UUID()
    let url: URL
}

#Preview {
    NavigationStack {
        GalleryView()
            .modelContainer(SampleData.shared.modelContainer)
    }
    .preferredColorScheme(.dark)
}

#Preview("Empty") {
    NavigationStack {
        GalleryView()
            .modelContainer(for: [VideoItem.self], inMemory: true)
    }
    .preferredColorScheme(.dark)
}

