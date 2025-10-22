// CameraSession.swift
import Foundation
@preconcurrency import AVFoundation
import Combine

actor CaptureService: NSObject {
    enum CaptureStatus {
        case idle
        case recording(duration: TimeInterval = 0.0)
        
        var isRecording: Bool {
            switch self {
            case .idle: return false
            case .recording: return true
            }
        }
        
        var currentTime: TimeInterval {
            if case .recording(let duration) = self {
                return duration
            }
            
            return .zero
        }
    }
    
    @Published private(set) var status: CaptureStatus = .idle
    
    nonisolated let previewSource: PreviewSource
    
    // Underlying capture objects (kept private)
    private let session = AVCaptureSession()
    private let movieOutput = AVCaptureMovieFileOutput()
    private var videoInput: AVCaptureDeviceInput?
    private var audioInput: AVCaptureDeviceInput?
    
    // The interval at which to update the recording time.
    private let refreshInterval = TimeInterval(0.25)
    private var timerCancellable: AnyCancellable?

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
        guard !movieOutput.isRecording else { return }
        
        Task {
            guard let connection = movieOutput.connection(with: .video) else {
                fatalError("Config error. No video connection found")
            }
            // Ensure output is attached (in case configure was customized)
            if !session.outputs.contains(movieOutput), session.canAddOutput(movieOutput) {
                session.addOutput(movieOutput)
            }

            if connection.isVideoStabilizationSupported {
                connection.preferredVideoStabilizationMode = .auto
            }
            
            // Start a timer to update the recording time.
            startMonitoringDuration()

            await MainActor.run {
                // Pass self as delegate; the delegate method is nonisolated and will not touch actor state directly.
                movieOutput.startRecording(to: url, recordingDelegate: self)
            }
        }
    }

    func stopRecording() {
        guard movieOutput.isRecording else { return }
        
        movieOutput.stopRecording()
        stopMonitoringDuration()
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

private extension CaptureService {
    // Starts a timer to update the recording time.
    func startMonitoringDuration() {
        status = .recording(duration: 0.0)
        
        timerCancellable = Timer.publish(every: refreshInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                
                // Hop back to the actor before mutating actor state.
                Task {
                    let duration = await self.movieOutput.recordedDuration.seconds
                    await self.updateStatusRecording(duration: duration)
                }
            }
    }
    
    /// Stops the timer and resets the time to `CMTime.zero`.
    func stopMonitoringDuration() {
        timerCancellable?.cancel()
        status = .idle
    }
    
    // Actor-isolated helper to set status safely.
    func updateStatusRecording(duration: TimeInterval) {
        status = .recording(duration: duration)
    }
}
