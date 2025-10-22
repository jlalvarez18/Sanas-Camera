// CameraSession.swift
import Foundation
@preconcurrency import AVFoundation

actor CaptureService: NSObject {
    nonisolated let previewSource: PreviewSource
    
    // Underlying capture objects (kept private)
    private let session = AVCaptureSession()
    private let movieOutput = AVCaptureMovieFileOutput()
    private var videoInput: AVCaptureDeviceInput?
    private var audioInput: AVCaptureDeviceInput?

    // Delegate proxy to forward recording callbacks to a target
    private var recordingDelegateTarget: (any AVCaptureFileOutputRecordingDelegate)?

    // Public inspection
    var isRunning: Bool {
        session.isRunning
    }

    var isRecording: Bool {
        movieOutput.isRecording
    }
    
    override init() {
        previewSource = DefaultPreviewSource(session: session)
    }

    // Configure session (idempotent). Returns the configured AVCaptureSession
    // so the caller on the main actor can attach it to an AVCaptureVideoPreviewLayer.
    func configure(preset: AVCaptureSession.Preset = .high,
                   cameraPosition: AVCaptureDevice.Position = .back,
                   includeAudio: Bool = true) throws -> AVCaptureSession {
        session.beginConfiguration()

        if session.canSetSessionPreset(preset) {
            session.sessionPreset = preset
        }

        // Video
        do {
            if let current = videoInput {
                session.removeInput(current)
                videoInput = nil
            }
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: cameraPosition)
            guard let vDevice = device else {
                session.commitConfiguration()
                throw NSError(domain: "CameraSession", code: -1, userInfo: [NSLocalizedDescriptionKey: "No camera available"])
            }
            let vInput = try AVCaptureDeviceInput(device: vDevice)
            if session.canAddInput(vInput) {
                session.addInput(vInput)
                videoInput = vInput
            }
        } catch {
            session.commitConfiguration()
            throw error
        }

        // Audio (optional)
        if includeAudio {
            if let current = audioInput {
                session.removeInput(current)
                audioInput = nil
            }
            if let mic = AVCaptureDevice.default(for: .audio) {
                do {
                    let aInput = try AVCaptureDeviceInput(device: mic)
                    if session.canAddInput(aInput) {
                        session.addInput(aInput)
                        audioInput = aInput
                    }
                } catch {
                    // ignore audio errors; proceed without audio
                }
            }
        }

        // Movie output
        if !session.outputs.contains(movieOutput), session.canAddOutput(movieOutput) {
            session.addOutput(movieOutput)
            if let connection = movieOutput.connection(with: .video),
               connection.isVideoStabilizationSupported {
                connection.preferredVideoStabilizationMode = .auto
            }
        }

        session.commitConfiguration()
        return session
    }

    func startRunning() {
        if !session.isRunning {
            session.startRunning()
        }
    }

    func stopRunning() {
        if session.isRunning {
            session.stopRunning()
        }
    }

    // Provide a delegate target to receive recording callbacks
    func setRecordingDelegateTarget(_ target: (any AVCaptureFileOutputRecordingDelegate)?) {
        self.recordingDelegateTarget = target
    }

    func startRecording(to url: URL) {
        Task {
            // Ensure output is attached (in case configure was customized)
            if !session.outputs.contains(movieOutput), session.canAddOutput(movieOutput) {
                session.addOutput(movieOutput)
            }

            if let connection = movieOutput.connection(with: .video),
               connection.isVideoStabilizationSupported {
                connection.preferredVideoStabilizationMode = .auto
            }

            await MainActor.run {
                // Pass self as delegate; the delegate method is nonisolated and will not touch actor state directly.
                movieOutput.startRecording(to: url, recordingDelegate: self)
            }
        }
    }

    func stopRecording() {
        if movieOutput.isRecording {
            movieOutput.stopRecording()
        }
    }
}

// MARK: - Delegate proxying

extension CaptureService: AVCaptureFileOutputRecordingDelegate {
    // Make delegate nonisolated; do not touch actor-isolated state directly.
    nonisolated func fileOutput(_ output: AVCaptureFileOutput,
                                didFinishRecordingTo outputFileURL: URL,
                                from connections: [AVCaptureConnection],
                                error: Error?) {
        // Hop into the actor to safely read the target, then forward on the main actor.
        Task { [weak self] in
            guard let self = self else { return }
            
            // Read actor state inside the actor
            guard let target = await self.recordingDelegateTarget else { return }

            // Forward to target on main actor (typical for UI updates)
            await MainActor.run {
                target.fileOutput(output,
                                  didFinishRecordingTo: outputFileURL,
                                  from: connections,
                                  error: error)
            }
        }
    }
}
