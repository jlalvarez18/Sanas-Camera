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
    
    struct RecordingResult {
        let videoURL: URL
        let thumbURL: URL
    }

    @Published private(set) var authorization: AuthorizationState = .notDetermined
    @Published private(set) var isSessionRunning: Bool = false
    @Published private(set) var isRecording: Bool = false
    @Published private(set) var lastError: String?
    
    // Make this a stored, published property that we update from observeState()
    @Published private(set) var captureStatus: CaptureService.CaptureStatus = .idle
    
    /// An object that provides the connection between the capture session and the video preview layer.
    var previewSource: PreviewSource { captureService.previewSource }

    // Actor encapsulating AVFoundation graph
    private let captureService = CaptureService()

    // Completion handler for recording
    private var recordingCompletion: ((VideoItem) -> Void)?
    
    // Keep a task reference so we can cancel observation if needed
    private var statusObserverTask: Task<Void, Never>?
    
    private var currentRecordingUUID: UUID?

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
                let _ = try await captureService.configure(
                    preset: .high,
                    cameraPosition: .back,
                    includeAudio: true
                )

                // Start running
                await captureService.startRunning()
                
                observeState()
                
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

    func startRecording(onSaved: @escaping (VideoItem) -> Void) {
        guard isSessionRunning else {
            lastError = "Session is not running."
            return
        }
        guard !isRecording else { return }

        recordingCompletion = onSaved
        
        let newUUID = UUID()
        currentRecordingUUID = newUUID

        // Create destination URL in Documents
        let outputURL = CameraModel.makeVideoURL(uuid: newUUID)

        Task {
            // Make sure we receive delegate callbacks
            await captureService.setRecordingDelegateTarget(self)
            // Start recording
            await captureService.startRecording(to: outputURL)
        }
    }

    func stopRecording() {
        guard isRecording else { return }
        Task {
            await captureService.stopRecording()
        }
    }
}

// MARK: - AVCaptureFileOutputRecordingDelegate

extension CameraModel: AVCaptureFileOutputRecordingDelegate {
    nonisolated func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        Task {
            guard let recordingUUID = await self.currentRecordingUUID else {
                return
            }
            
            let thumbURL = try await generateThumbnail(forVideoAt: outputFileURL, at: CMTime(seconds: 1, preferredTimescale: 600), recordingUUID: recordingUUID)
            
            await MainActor.run { [weak self] in
                guard let self = self else {
                    return
                }
                
                let completion = self.recordingCompletion
                
                if let error {
                    self.lastError = "Recording failed: \(error.localizedDescription)"
                } else if let completion {
                    // Store only filenames (stable across app restarts/reinstalls)
                    let item = VideoItem(
                        timestamp: Date(),
                        filePath: outputFileURL.lastPathComponent,
                        thumbFilePath: thumbURL.lastPathComponent
                    )
                    completion(item)
                }

                self.recordingCompletion = nil
            }
        }
    }
    
    func generateThumbnail(forVideoAt url: URL, at time: CMTime, recordingUUID: UUID) async throws -> URL {
        let asset = AVURLAsset(url: url)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.requestedTimeToleranceAfter = .zero
        imageGenerator.requestedTimeToleranceBefore = .zero
        
        let cgImage = try await imageGenerator.image(at: time).image
        
        let uiImage = UIImage(cgImage: cgImage)
        
        guard let jpgData = uiImage.jpegData(compressionQuality: 0.7) else {
            throw NSError(domain: "CameraModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unable to generate thumbnail data"])
        }
        
        let outputURL = CameraModel.makeThumbnailURL(uuid: recordingUUID)
        
        try jpgData.write(to: outputURL, options: .atomic)
        
        return outputURL
    }
}

// MARK: - Private Functions

private extension CameraModel {
    static func translate(_ status: AVAuthorizationStatus) -> AuthorizationState {
        switch status {
        case .authorized: return .authorized
        case .denied: return .denied
        case .restricted: return .restricted
        case .notDetermined: return .notDetermined
        @unknown default: return .denied
        }
    }
    
    static func makeVideoURL(uuid: UUID) -> URL {
        return makeDocumentsURLWithTimestamp(uuid: uuid, suffix: "VID_", extension: "mov")
    }
    
    static func makeThumbnailURL(uuid: UUID) -> URL {
        return makeDocumentsURLWithTimestamp(uuid: uuid, suffix: "THUMB_", extension: "jpg")
    }

    static func makeDocumentsURLWithTimestamp(uuid: UUID, suffix: String, extension ext: String) -> URL {
        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
        
        let name = "\(suffix)\(uuid.uuidString).\(ext)"
        
        return docs.appendingPathComponent(name, isDirectory: false)
    }
    
    func observeState() {
        // Cancel previous observer if any
        statusObserverTask?.cancel()
        
        // Bridge the actor's @Published status to our @Published captureStatus on the main actor
        statusObserverTask = Task { [weak self] in
            guard let self else { return }
            // Access the actor's publisher in the actor context, then iterate its AsyncSequence of values
            for await status in await captureService.$status.values {
                // Hop to the main actor (we are already @MainActor, but this keeps intent clear)
                await MainActor.run {
                    self.captureStatus = status
                    self.isRecording = status.isRecording
                }
            }
        }
    }
}

