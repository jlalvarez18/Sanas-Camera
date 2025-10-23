//
//  CameraFooterView.swift
//  Sanas Camera
//
//  Created by Juan Alvarez on 10/22/25.
//

import SwiftUI
import SwiftData
import Lottie

struct CameraFooterView: View {
    @EnvironmentObject private var camera: CameraModel
    @Environment(\.modelContext) private var context
    
    // Making sure to only fetch 1 item as that is all we need
    static var descriptor: FetchDescriptor<VideoItem> {
        var descriptor = FetchDescriptor<VideoItem>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
        descriptor.fetchLimit = 1
        
        return descriptor
    }
    
    @Query(descriptor) private var latestVideos: [VideoItem]

    // Callback provided by the parent to trigger navigation
    var onShowLibrary: () -> Void

    private let footerHeight: CGFloat = 120
    private let recordSize: CGFloat = 64
    private let librarySize: CGFloat = 50
    private let libraryCornerRadius: CGFloat = 16
    private let edgePadding: CGFloat = 16

    init(onShowLibrary: @escaping () -> Void = {}) {
        self.onShowLibrary = onShowLibrary
    }
    
    @State private var playbackMode: LottiePlaybackMode = .paused
    @State private var startAnimation: DotLottieFile?
    @State private var stopAnimation: DotLottieFile?
    @State private var currentDotLottie: DotLottieFile?

    var body: some View {
        ZStack {
            // Centered record button (always remains centered)
            HStack {
                Spacer(minLength: 0)

                Button {
                    if camera.isRecording {
                        camera.stopRecording()
                    } else {
                        camera.startRecording { item in
                            // Persist to SwiftData
                            context.insert(item)
                        }
                    }
                } label: {
                    if let file = currentDotLottie {
                        LottieView(dotLottieFile: file)
                            .playbackMode(playbackMode)
                            .animationDidFinish { completed in
                                playbackMode = .paused
                            }
                            .resizable()
                            .frame(width: recordSize, height: recordSize)
                            .onChange(of: camera.isRecording) { oldValue, newValue in
                                if newValue {
                                    currentDotLottie = startAnimation
                                } else {
                                    currentDotLottie = stopAnimation
                                }
                                
                                DispatchQueue.main.async {
                                    playbackMode = .playing(.fromProgress(0, toProgress: 1, loopMode: .playOnce))
                                }
                            }
                    }
                }
                .buttonStyle(.plain)
                .disabled(startAnimation == nil || stopAnimation == nil)
                .accessibilityLabel(camera.isRecording ? "Stop Recording" : "Start Recording")

                Spacer(minLength: 0)
            }
            .task {
                do {
                    startAnimation = try await DotLottieFile.named("Video_Start")
                    stopAnimation = try await DotLottieFile.named("Video_Stop")
                    
                    currentDotLottie = startAnimation
                } catch {
                    
                }
            }

            // Trailing photo library button (always hugs the right edge)
            HStack {
                Spacer()

                Button {
                    onShowLibrary()
                } label: {
                    // Replace with a real thumbnail when available
                    if let latestVideo = latestVideos.first, let image = latestVideo.thumbImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: librarySize, height: librarySize)
                            .contentTransition(.opacity)
                            .animation(.easeInOut(duration: 0.3), value: latestVideo.persistentModelID)
                            .clipShape(RoundedRectangle(cornerRadius: libraryCornerRadius, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: libraryCornerRadius, style: .continuous)
                                    .stroke(Color.white.opacity(0.9), lineWidth: 2)
                            )
                    } else {
                        Image(systemName: "photo.stack")
                            .resizable()
                            .scaledToFit()
                            .frame(width: librarySize, height: librarySize)
                    }
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
    NavigationStack {
        VStack(spacing: 0) {
            Color.white
                .frame(maxHeight: .infinity)
            CameraFooterView()
        }
        .navigationBarTitleDisplayMode(.inline)
    }
    .preferredColorScheme(.dark)
    .environmentObject(CameraModel())
    .modelContainer(for: VideoItem.self, inMemory: true)
}
