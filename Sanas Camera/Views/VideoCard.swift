//
//  VideoCard.swift
//  Sanas Camera
//
//  Created by Juan Alvarez on 10/23/25.
//

import SwiftUI
import LucideIcons

struct VideoCard: View {
    let video: VideoItem
    
    let onTap: (VideoItem) -> Void
    
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
            VStack {
                Spacer()
                
                Button {
                    onTap(video)
                } label: {
                    Image(uiImage: Lucide.play)
                        .resizable()
                        .renderingMode(.template)
                        .frame(width: 40, height: 40)
                        .foregroundStyle(.white)
                }
            }
            .padding(.bottom, 24.0)
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.clear)
                .shadow(color: .black.opacity(0.25), radius: 14, x: 0, y: 10)
        )
        .compositingGroup()
        .onTapGesture {
            onTap(video)
        }
    }
}

#Preview {
    let item = VideoItem.sampleData().first!
    
    List {
        VideoCard(video: item) { _ in
            
        }
    }
    
}
