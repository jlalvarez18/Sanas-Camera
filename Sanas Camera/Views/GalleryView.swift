//
//  VideoLibraryView.swift
//  Sanas Camera
//
//  Created by Juan Alvarez on 10/22/25.
//

import SwiftUI
import SwiftData

struct GalleryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \VideoItem.timestamp, order: .reverse) private var videos: [VideoItem]

    var body: some View {
        Group {
            if videos.isEmpty {
                Text("No Videos Recorded")
            } else {
                List {
                    ForEach(videos) { video in
                        Text(video.filePath)
                    }
                }
            }
        }
        .navigationTitle("Gallery")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        GalleryView()
            .modelContainer(for: [VideoItem.self], inMemory: true)
    }
    .preferredColorScheme(.dark)
}

