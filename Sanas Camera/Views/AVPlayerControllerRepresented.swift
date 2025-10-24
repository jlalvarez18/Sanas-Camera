//
//  AVPlayerControllerRepresented.swift
//  Sanas Camera
//
//  Created by Juan Alvarez on 10/23/25.
//

import SwiftUI
import AVKit

struct AVPlayerControllerRepresented: UIViewControllerRepresentable {
    typealias UIViewControllerType = AVPlayerViewController
    
    @Binding var player: AVPlayer
    @Binding var showPlaybackControls: Bool
    
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = showPlaybackControls
        controller.view.isUserInteractionEnabled = false
        
        return controller
    }
    
    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        uiViewController.view.isUserInteractionEnabled = false
    }
}
