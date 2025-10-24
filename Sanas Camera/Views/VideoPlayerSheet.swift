//
//  VideoPlayerSheet.swift
//  Sanas Camera
//
//  Created by Juan Alvarez on 10/23/25.
//

import SwiftUI
import AVKit
import LucideIcons

struct VideoPlayerSheet: View, Identifiable {
    let id = UUID()
    let url: URL
    
    @StateObject private var playerViewModel: PlayerViewModel
    
    @State private var showControls = true
    @State private var timer: Timer?
    
    init(url: URL) {
        self.url = url
        _playerViewModel = StateObject(wrappedValue: PlayerViewModel(url: url))
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                AVPlayerControllerRepresented(
                    player: .constant(playerViewModel.player),
                    showPlaybackControls: .constant(false)
                )
                .onAppear {
                    // You can auto-play if desired:
                     DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                         playerViewModel.player.play()
                         
                         startTimer(timeInterval: 2)
                     }
                }
                
                // Tap-capturing overlay above the player view
                Color.black.opacity(0.001) // effectively transparent but receives touches
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation {
                            showControls.toggle()
                        }
                        
                        if playerViewModel.isPlaying {
                            startTimer(timeInterval: 3)
                        }
                    }
                
                if showControls {
                    VideoPlayerControls(
                        isPlaying: Binding(
                            get: { playerViewModel.isPlaying },
                            set: { _ in /* no-op; playback controlled via player binding */ }
                        ),
                        player: .constant(playerViewModel.player),
                        timer: $timer,
                        showPlayerControlButtons: $showControls
                    )
                    // Ensure controls are above the overlay
                    .zIndex(1)
                }
            }
        }
    }
    
    private func startTimer(timeInterval: TimeInterval) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: timeInterval, repeats: false) { _ in
            withAnimation {
                showControls = false
            }
        }
    }
}

private struct VideoPlayerControls: View {
    @Environment(\.dismiss) var dismiss
    
    @Binding var isPlaying: Bool
    @Binding var player: AVPlayer
    
    @Binding var timer: Timer?
    @Binding var showPlayerControlButtons: Bool
    
    var body: some View {
        // Top Close Button
        VStack {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.glass)
                
                Spacer()
            }
            Spacer()
        }
        .padding(20)
        
        // Centered Play Button
        VStack {
            Spacer()
            
            Button {
                withAnimation {
                    if isPlaying {
                        player.pause()
                    } else {
                        player.play()
                    }
                }
                
                startTimer(timeInterval: 3)
            } label: {
                Image(uiImage: isPlaying ? Lucide.pause : Lucide.play)
                    .resizable()
                    .renderingMode(.template)
                    .foregroundStyle(.white)
                    .frame(width: 45, height: 45)
            }
            
            Spacer()
        }
    }
    
    private func startTimer(timeInterval: Double) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: timeInterval, repeats: false) { _ in
            withAnimation {
                showPlayerControlButtons = false
            }
        }
    }
}

#Preview {
    // Provide a valid URL for preview or adjust preview as needed
     VideoPlayerSheet(url: URL(string: "https://video-previews.elements.envatousercontent.com/h264-video-previews/315b5d0f-cca5-41c0-824f-e99e2dcfbe6d/40108191.mp4")!)
}
