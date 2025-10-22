//
//  CameraModel.swift
//  Sanas Camera
//
//  Created by Juan Alvarez on 10/22/25.
//

import Foundation
import AVFoundation
import UIKit
import Combine

@MainActor
final class CameraModel: NSObject, ObservableObject {

    enum AuthorizationState: Equatable {
        case notDetermined
        case authorized
        case denied
        case restricted
    }

    @Published private(set) var authorization: AuthorizationState = .notDetermined
    @Published private(set) var isSessionRunning: Bool = false
    @Published private(set) var isRecording: Bool = false
    @Published private(set) var lastError: String?
    
    /// An object that provides the connection between the capture session and the video preview layer.
    var previewSource: PreviewSource { captureService.previewSource }

    // Actor encapsulating AVFoundation graph
    private let captureService = CaptureService()

    // Completion handler for recording
    private var recordingCompletion: ((URL) -> Void)?

    override init() {
        // Precompute current authorization
        self.authorization = CameraModel.translate(AVCaptureDevice.authorizationStatus(for: .video))
    }

    // MARK: - Permissions

    func requestPermissions() async {
        // Camera
        let camGranted = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            AVCaptureDevice.requestAccess(for: .video) { granted in
                continuation.resume(returning: granted)
            }
        }

        // Microphone
        let micGranted = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }

        let camStatus = AVCaptureDevice.authorizationStatus(for: .video)
        if camGranted && micGranted && camStatus == .authorized {
            authorization = .authorized
        } else {
            switch camStatus {
            case .denied: authorization = .denied
            case .restricted: authorization = .restricted
            case .authorized:
                // Camera ok but mic not granted still means we can run session but recording will lack audio.
                authorization = micGranted ? .authorized : .authorized
            case .notDetermined: authorization = .notDetermined
            @unknown default: authorization = .denied
            }
        }
    }

    // MARK: - Session lifecycle

    func startSession() {
        guard authorization == .authorized else {
            self.lastError = "Camera not authorized."
            return
        }

        Task {
            do {
                // Configure the actor-backed session
                let configuredSession = try await captureService.configure(
                    preset: .high,
                    cameraPosition: .back,
                    includeAudio: true
                )

                // Start running
                await captureService.startRunning()
                isSessionRunning = true
            } catch {
                lastError = "Failed to start session: \(error.localizedDescription)"
                isSessionRunning = false
            }
        }
    }

    func stopSession() {
        Task {
            await captureService.stopRunning()
            isSessionRunning = false
        }
    }

    // MARK: - Recording

    func startRecording(onSaved: @escaping (URL) -> Void) {
        guard isSessionRunning else {
            lastError = "Session is not running."
            return
        }
        guard !isRecording else { return }

        recordingCompletion = onSaved

        // Create destination URL in Documents
        let outputURL = CameraModel.makeDocumentsURLWithTimestamp(extension: "mov")

        Task {
            // Make sure we receive delegate callbacks
            await captureService.setRecordingDelegateTarget(self)
            // Start recording
            await captureService.startRecording(to: outputURL)
            isRecording = true
        }
    }

    func stopRecording() {
        guard isRecording else { return }
        Task {
            await captureService.stopRecording()
            // isRecording will be set to false in delegate callback
        }
    }
}

// MARK: - AVCaptureFileOutputRecordingDelegate

extension CameraModel: AVCaptureFileOutputRecordingDelegate {
    nonisolated func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        Task {
            await MainActor.run { [weak self] in
                guard let self = self else {
                    return
                }

                let completion = self.recordingCompletion

                self.isRecording = false
                
                if let error {
                    self.lastError = "Recording failed: \(error.localizedDescription)"
                } else if let completion {
                    completion(outputFileURL)
                }

                self.recordingCompletion = nil
            }
        }
    }
}

// MARK: - Private Functions

extension CameraModel {
    private static func translate(_ status: AVAuthorizationStatus) -> AuthorizationState {
        switch status {
        case .authorized: return .authorized
        case .denied: return .denied
        case .restricted: return .restricted
        case .notDetermined: return .notDetermined
        @unknown default: return .denied
        }
    }

    private static func makeDocumentsURLWithTimestamp(extension ext: String) -> URL {
        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let name = "VID_\(formatter.string(from: Date())).\(ext)"
        return docs.appendingPathComponent(name, isDirectory: false)
    }
}
