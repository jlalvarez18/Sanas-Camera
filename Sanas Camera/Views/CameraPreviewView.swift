//
//  CameraPreviewView.swift
//  Sanas Camera
//
//  Created by Juan Alvarez on 10/22/25.
//

import SwiftUI

struct CameraPreviewView: View {
    @EnvironmentObject private var camera: CameraModel
    
    private let cornerRadius: CGFloat = 16
    private let buttonSize: CGFloat = 44
    private let buttonPadding: CGFloat = 16

    var body: some View {
        GeometryReader { proxy in
            // We now have an explicit size from the parent: proxy.size.
            ZStack {
                CameraPreview(source: camera.previewSource)
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height) // <- bind to parent size
                    .clipped()

                LinearGradient(
                    colors: [.clear, .clear, .black.opacity(0.28), .black.opacity(0.5)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .allowsHitTesting(false)

                HStack {
                    RoundedButton(
                        systemName: "bolt.fill",
                        foreground: .white,
                        background: .black.opacity(0.35),
                        size: buttonSize
                    ) {
                        // TODO: action for left button
                    }

                    Spacer()

                    RoundedButton(
                        systemName: "camera.viewfinder",
                        foreground: .white,
                        background: .black.opacity(0.35),
                        size: buttonSize
                    ) {
                        // TODO: action for right button
                    }
                }
                .padding(.horizontal, buttonPadding)
                .padding(.bottom, buttonPadding)
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
}
