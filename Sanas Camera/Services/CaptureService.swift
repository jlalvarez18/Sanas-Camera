// CameraSession.swift
import Foundation
@preconcurrency internal import AVFoundation
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
    @Published private(set) var isTorchAvailable: Bool = false
    @Published private(set) var torchMode: AVCaptureDevice.TorchMode = .off
    @Published private(set) var isTorchActive: Bool = false
    private var wantsTorchOn: Bool = false
    
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
    
    private var currentDevice: AVCaptureDevice?
    private var torchIsAvailableObservation: NSKeyValueObservation?
    private var torchIsActiveObservation: NSKeyValueObservation?
    private var torchModeObservation: NSKeyValueObservation?

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
    
    deinit {
        torchIsAvailableObservation?.invalidate()
        torchIsActiveObservation?.invalidate()
        torchModeObservation?.invalidate()
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
            
            configureDevice(vDevice)
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
                // Re-assert torch shortly after recording starts (some formats reset torch)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    Task { [weak self] in
                        await self?.reassertTorchIfNeeded()
                    }
                }
            }
        }
    }

    func stopRecording() {
        guard movieOutput.isRecording else { return }
        
        movieOutput.stopRecording()
        stopMonitoringDuration()
    }
    
    func toggleTorch() {
        guard let currentDevice = self.currentDevice else { return }

        wantsTorchOn.toggle()

        do {
            try currentDevice.lockForConfiguration()
            defer { currentDevice.unlockForConfiguration() }

            if wantsTorchOn,
               currentDevice.hasTorch,
               currentDevice.isTorchAvailable,
               currentDevice.isTorchModeSupported(.on) {
                try? currentDevice.setTorchModeOn(level: AVCaptureDevice.maxAvailableTorchLevel)
                setTorchMode(.on)
            } else {
                if currentDevice.isTorchModeSupported(.off) {
                    currentDevice.torchMode = .off
                    setTorchMode(.off)
                }
            }
        } catch {
            print("Error locking device for torch config: \(error)")
        }
    }

    private func reassertTorchIfNeeded() {
        guard wantsTorchOn, let device = currentDevice else { return }
        guard device.hasTorch, device.isTorchAvailable, device.isTorchModeSupported(.on) else { return }

        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            if device.torchMode != .on {
                try? device.setTorchModeOn(level: AVCaptureDevice.maxAvailableTorchLevel)
                setTorchMode(.on)
            }
        } catch {
            print("Error reasserting torch: \(error)")
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
    
    func setTorchMode(_ mode: AVCaptureDevice.TorchMode) {
        self.torchMode = mode
    }
    
    func setIsTorchAvailable(_ isAvailable: Bool) {
        self.isTorchAvailable = isAvailable
    }
    
    func setIsTorchActive(_ active: Bool) {
        self.isTorchActive = active
    }
    
    func configureDevice(_ device: AVCaptureDevice) {
        self.currentDevice = device
        
        torchIsAvailableObservation?.invalidate()
        
        torchIsAvailableObservation = device.observe(\.hasTorch, options: [.initial, .new], changeHandler: { [weak self] d, c in
            guard let self else { return }
            
            Task {
                await self.setIsTorchAvailable(device.hasTorch)
            }
        })
        
        // Observe actual torch activity (LED on/off)
        torchIsActiveObservation?.invalidate()
        torchIsActiveObservation = device.observe(\.isTorchActive, options: [.initial, .new], changeHandler: { [weak self] dev, _ in
            guard let self = self else { return }
            Task { await self.setIsTorchActive(dev.isTorchActive) }
            // If it turned off but user wanted it on, try to reassert
            if !dev.isTorchActive {
                Task { [weak self] in await self?.reassertTorchIfNeeded() }
            }
        })

        // Observe mode changes as well (e.g., system toggles)
        torchModeObservation?.invalidate()
        torchModeObservation = device.observe(\.torchMode, options: [.initial, .new], changeHandler: { [weak self] dev, _ in
            guard let self = self else { return }
            Task { await self.setTorchMode(dev.torchMode) }
        })
    }
}
