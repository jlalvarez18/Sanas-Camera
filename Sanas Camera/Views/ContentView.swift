//
//  ContentView.swift
//  Sanas Camera
//
//  Created by Juan Alvarez on 10/22/25.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @StateObject private var camera = CameraModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                Image("sanas_logo")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 24)
                    .accessibilityHidden(true)

                CameraPreviewView()
                    .environmentObject(camera)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 24)

                CameraFooterView()
                    .environmentObject(camera)
            }
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await camera.requestPermissions()
                
                camera.startSession()
            }
            .onChange(of: scenePhase) { _, newPhase in
                // we want to make sure that when the app enters the background it will stop the camera session
                if newPhase == .background {
                    camera.stopSession()
                } else if newPhase == .active, camera.authorization == .authorized {
                    camera.startSession()
                }
            }
            .onDisappear() {
                camera.stopSession()
            }
        }
        .preferredColorScheme(.dark)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: VideoItem.self, inMemory: true)
}
