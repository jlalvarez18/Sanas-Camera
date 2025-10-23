//
//  CameraPreviewView.swift
//  Sanas Camera
//
//  Created by Juan Alvarez on 10/22/25.
//

import SwiftUI
import LucideIcons
internal import AVFoundation

struct CameraPreviewView: View {
    @EnvironmentObject private var camera: CameraModel
    
    private let cornerRadius: CGFloat = 16
    private let buttonSize: CGFloat = 50
    private let buttonIconSize: CGFloat = 24
    private let buttonPadding: CGFloat = 16
    
    @State private var blurRadius = CGFloat.zero

    var body: some View {
        GeometryReader { proxy in
            // We now have an explicit size from the parent: proxy.size.
            ZStack {
                CameraPreview(source: camera.previewSource)
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height) // <- bind to parent size
                    .clipped()
                    .blur(radius: blurRadius, opaque: true)
                    .onChange(of: camera.isSwitchingCameras, updateBlurRadius(_:_:))

                LinearGradient(
                    colors: [.clear, .clear, .black.opacity(0.28), .black.opacity(0.5)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .allowsHitTesting(false)

                VStack {
                    HStack {
                        if camera.captureStatus.isRecording {
                            RecordingTimeView(time: camera.captureStatus.currentTime)
                        }
                    }
                    
                    Spacer()
                    
                    HStack {
                        if camera.isTorchAvailable {
                            Button {
                                camera.toggleTorchLight()
                            } label: {
                                Image(uiImage: camera.torchMode == .on ? Lucide.zap : Lucide.zapOff)
                                    .resizable()
                                    .renderingMode(.template)
                                    .foregroundStyle(.white)
                                    .frame(width: buttonIconSize, height: buttonIconSize)
                            }
                            .frame(width: buttonSize, height: buttonSize)
                        }
                        
                        Spacer()
                        
                        Button {
                            camera.switchCamera()
                        } label: {
                            Image(uiImage: Lucide.switchCamera)
                                .resizable()
                                .renderingMode(.template)
                                .foregroundStyle(.white)
                                .frame(width: buttonIconSize, height: buttonIconSize)
                        }
                        .frame(width: buttonSize, height: buttonSize)
                        .disabled(camera.captureStatus.isRecording)
                        .allowsHitTesting(!camera.isSwitchingCameras)
                    }
                }
                .padding(.horizontal, buttonPadding)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.35), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .frame(width: proxy.size.width, height: proxy.size.height) // ensure overlay matches exact size
        }
        // Let the parent decide the size; GeometryReader will adapt to it.
    }
    
    func updateBlurRadius(_: Bool, _ isSwitching: Bool) {
        withAnimation {
            blurRadius = isSwitching ? 30 : 0
        }
    }
}

// MARK: - Reusable rounded button
private struct RoundedButton: View {
    let systemName: String
    var foreground: Color = .white
    var background: Color = .black.opacity(0.35)
    var size: CGFloat = 44
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(foreground)
                .frame(width: size, height: size)
                .background(
                    RoundedRectangle(cornerRadius: size / 2, style: .continuous)
                        .fill(background)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: size / 2, style: .continuous)
                        .strokeBorder(.white.opacity(0.25), lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: size / 2, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isButton)
    }
}

#Preview {
    VStack {
        CameraPreviewView()
            .frame(maxWidth: .infinity, maxHeight: 700)
            .padding(.horizontal, 24)
    }
    .environmentObject(CameraModel())
    .preferredColorScheme(.dark)
}
