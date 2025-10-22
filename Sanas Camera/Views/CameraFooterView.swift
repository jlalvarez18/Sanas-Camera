//
//  CameraFooterView.swift
//  Sanas Camera
//
//  Created by Juan Alvarez on 10/22/25.
//

import SwiftUI
import SwiftData

struct CameraFooterView: View {
    @EnvironmentObject private var camera: CameraModel
    
    @Environment(\.modelContext) private var context
    
    private let footerHeight: CGFloat = 120
    private let recordSize: CGFloat = 64
    private let librarySize: CGFloat = 50
    private let libraryCornerRadius: CGFloat = 16
    private let edgePadding: CGFloat = 16

    var body: some View {
        ZStack {
            // Centered record button (always remains centered)
            HStack {
                Spacer(minLength: 0)

                Button {
                    if camera.isRecording {
                        camera.stopRecording()
                    } else {
                        camera.startRecording { url in
                            // Persist to SwiftData as VideoItem
                            // You can inject modelContext here or handle in a higher level.
                            // Example (requires Environment(\.modelContext)):
                             let item = VideoItem(timestamp: Date(), filePath: url.path)
                             context.insert(item)
                        }
                    }
                } label: {
                    Image(systemName: camera.isRecording ? "stop.circle" : "record.circle")
                        .resizable()
                        .frame(width: recordSize, height: recordSize)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(camera.isRecording ? "Stop Recording" : "Start Recording")

                Spacer(minLength: 0)
            }

            // Trailing photo library button (always hugs the right edge)
            HStack {
                Spacer()

                Button {
                    // TODO: Open photo library
                } label: {
                    // Replace with a real thumbnail when available
                    Image(systemName: "photo.stack")
                        .resizable()
                        .scaledToFit()
                        .frame(width: librarySize, height: librarySize)
                        .clipShape(RoundedRectangle(cornerRadius: libraryCornerRadius, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: libraryCornerRadius, style: .continuous)
                                .stroke(Color.white.opacity(0.9), lineWidth: 2)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Video Library")
            }
            
        }
        .padding(.vertical, 32)
        .padding(.horizontal, edgePadding)
        .frame(maxWidth: .infinity)
        .background(Color.black.opacity(0.95))
    }
}

#Preview {
    VStack(spacing: 0) {
        Color.white
            .frame(maxHeight: .infinity)
        CameraFooterView()
    }
    .preferredColorScheme(.dark)
    .environmentObject(CameraModel())
    .modelContainer(for: VideoItem.self, inMemory: true)
}
