//
//  PlayerViewModel.swift
//  Sanas Camera
//
//  Created by Juan Alvarez on 10/23/25.
//

import Combine
import SwiftUI
internal import AVFoundation

class PlayerViewModel: ObservableObject {
    let player: AVPlayer
    
    @Published var isPlaying: Bool = false
    
    private var timeControlStatusObserver: AnyCancellable?
    private var didPlayToEndTimeObserver: AnyCancellable?
    
    init(url: URL) {
        self.player = AVPlayer(url: url)
        
        setupObservers()
    }
    
    deinit {
        timeControlStatusObserver?.cancel()
        didPlayToEndTimeObserver?.cancel()
    }
    
    private func setupObservers() {
        timeControlStatusObserver = player.publisher(for: \.timeControlStatus)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self else { return }
                
                self.isPlaying = (status == .playing)
            }
        
        didPlayToEndTimeObserver = NotificationCenter.default.publisher(for: AVPlayerItem.didPlayToEndTimeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] result in
                guard let self else { return }
                
                self.player.seek(to: .zero)
            }
    }
}
