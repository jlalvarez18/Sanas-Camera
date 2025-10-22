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

    // Navigation
    enum Route: Hashable {
        case library
    }

    @State private var path: [Route] = []

    var body: some View {
        NavigationStack(path: $path) {
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

                CameraFooterView {
                    // Request push to the library
                    path.append(.library)
                }
                .environmentObject(camera)
            }
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await camera.requestPermissions()
                camera.startSession()
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .background {
                    camera.stopSession()
                } else if newPhase == .active, camera.authorization == .authorized {
                    camera.startSession()
                }
            }
            .onDisappear() {
                camera.stopSession()
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .library:
                    GalleryView()
                        .navigationTitle("Gallery")
                        .navigationBarTitleDisplayMode(.inline)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: VideoItem.self, inMemory: true)
}

