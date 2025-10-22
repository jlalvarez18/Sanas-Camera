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
                GeometryReader { proxy in
                    let width = proxy.size.width
                    let cardW = cardWidth(for: width)
                    let cardH = cardHeight(for: cardW)

                    // Full-width horizontal carousel with paging-like snapping
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 16) {
                            ForEach(videos.indices, id: \.self) { index in
                                let video = videos[index]
                                VideoCard(video: video)
                                    .frame(width: cardW, height: cardH)
                                    .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    .onTapGesture {
                                        if let url = video.localVideoURL ?? URL(string: video.filePath) {
                                            selectedVideo = IdentifiedURL(url: url)
                                        } else {
                                            print("GalleryView: Invalid video.filePath: \(video.filePath)")
                                        }
                                    }
                                    .scrollTargetLayout() // enables paging target on iOS 17+
                            }
                        }
                        .padding(.vertical, 12)
                    }
                    .scrollTargetBehavior(.paging) // iOS 17+; provides snapping/paging feel
                    .contentMargins(.horizontal, horizontalPadding, for: .scrollContent) // keeps first/last centered
                    .safeAreaPadding(.horizontal, 0)
                    .sheet(item: $selectedVideo) { item in
                        AVPlayerView(url: item.url)
                            .ignoresSafeArea()
                    }
                }
            }
        }
        .navigationTitle("Gallery")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    // MARK: - Layout helpers
    
    private func cardWidth(for containerWidth: CGFloat) -> CGFloat {
        return max(280, min(containerWidth * 0.86, 520))
    }
    
    private func cardHeight(for cardWidth: CGFloat) -> CGFloat {
        cardWidth * (16.0 / 9.0)
    }
    
    private var horizontalPadding: CGFloat { 20 }
}

// MARK: - Video Card

private struct VideoCard: View {
    let video: VideoItem
    
    var body: some View {
        ZStack {
            // Thumbnail
            Group {
                if let image = video.thumbImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .onAppear {
                            #if DEBUG
                            print("VideoCard: Showing LOCAL thumbnail for \(video.debugThumbDescription)")
                            #endif
                        }
                } else if let remoteURL = video.remoteThumbURL {
                    AsyncImage(url: remoteURL) { phase in
                        switch phase {
                        case .empty:
                            Color.secondary.opacity(0.15)
                                .overlay(ProgressView())
                        case .success(let img):
                            img
                                .resizable()
                                .scaledToFill()
                                .onAppear {
                                    #if DEBUG
                                    print("VideoCard: Showing REMOTE thumbnail: \(remoteURL.absoluteString)")
                                    #endif
                                }
                        case .failure(let error):
                            Color.secondary.opacity(0.15)
                                .overlay(Image(systemName: "photo").font(.largeTitle))
                                .onAppear {
                                    #if DEBUG
                                    print("VideoCard: Remote thumbnail failed \(remoteURL.absoluteString), error: \(String(describing: error))")
                                    #endif
                                }
                        @unknown default:
                            Color.secondary.opacity(0.15)
                        }
                    }
                } else {
                    Color.secondary.opacity(0.15)
                        .overlay(Image(systemName: "photo").font(.largeTitle))
                        .onAppear {
                            #if DEBUG
                            print("VideoCard: No thumbnail available for \(video.debugThumbDescription)")
                            #endif
                        }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            
            // Play overlay
            Button {
                
            } label: {
                Image(uiImage: Lucide.play)
                    .resizable()
                    .renderingMode(.template)
                    .frame(width: 40, height: 40)
                    .foregroundStyle(.white)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.clear)
                .shadow(color: .black.opacity(0.25), radius: 14, x: 0, y: 10)
        )
        .compositingGroup()
    }
}

// MARK: - Simple AVPlayer Sheet

private struct AVPlayerView: View, Identifiable {
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

// MARK: - VideoItem helpers

extension VideoItem {
    // Documents directory URL
    private var documentsDir: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    }
    
    // Build a local URL for a possibly filename-only path.
    // Supports legacy absolute file URLs (file:///...) and new filename-only values.
    private func localURL(from storedPath: String) -> URL? {
        if let url = URL(string: storedPath), url.isFileURL {
            // Legacy absolute file URL
            return url
        } else if !storedPath.isEmpty {
            // Treat as filename relative to Documents
            return documentsDir.appendingPathComponent(storedPath, isDirectory: false)
        } else {
            return nil
        }
    }
    
    // Local video URL using filename-based storage (or legacy absolute)
    var localVideoURL: URL? {
        localURL(from: filePath)
    }
    
    // Local thumbnail URL using filename-based storage (or legacy absolute)
    var localThumbURL: URL? {
        localURL(from: thumbFilePath)
    }
    
    var localThumbExists: Bool {
        guard let url = localThumbURL else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }
    
    var thumbImage: UIImage? {
        guard let url = localThumbURL else { return nil }
        guard FileManager.default.fileExists(atPath: url.path) else {
            #if DEBUG
            print("VideoItem: Local thumbnail missing at path: \(url.path)")
            #endif
            return nil
        }
        return UIImage(contentsOfFile: url.path)
    }
    
    // Remote thumbnail URL (only http/https)
    var remoteThumbURL: URL? {
        guard let url = URL(string: thumbFilePath),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else {
            return nil
        }
        return url
    }
    
    var debugThumbDescription: String {
        if let local = localThumbURL {
            return "local: \(local.path) exists=\(localThumbExists)"
        } else if let remote = remoteThumbURL {
            return "remote: \(remote.absoluteString)"
        } else {
            return "invalid or empty path: \(thumbFilePath)"
        }
    }
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

