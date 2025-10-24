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
    
    // An object the service uses to retrieve capture devices.
    private let deviceLookup = DeviceLookup()
    
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
    
    // The device for the active video input.
    private var currentDevice: AVCaptureDevice {
        guard let device = videoInput?.device else {
            fatalError("No device found for current video input.")
        }
        return device
    }
    
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
    
    enum SetupState {
        case idle
        case configuring
        case ready
    }
    
    private var setupState: SetupState = .idle

    // Configure session (idempotent). Returns the configured AVCaptureSession
    // so the caller on the main actor can attach it to an AVCaptureVideoPreviewLayer.
    func configure(preset: AVCaptureSession.Preset = .high, cameraPosition: AVCaptureDevice.Position = .back) async throws {
        // Prevent re-entrant configuration across suspension points
        guard setupState == .idle else { return }
        
        // Mark as configuring *before* the first await so a second caller bails out
        setupState = .configuring
        
        // Always clear the flag at exit
        defer {
            // only change it back to idle if the setup failed
            if setupState == .configuring {
                setupState = .idle
            }
        }
        
        do {
            let defaultCamera = try await deviceLookup.defaultCamera
            let defaultMic = try await deviceLookup.defaultMic
            
            if let current = videoInput {
                session.removeInput(current)
                videoInput = nil
            }
            
            if let current = audioInput {
                session.removeInput(current)
                audioInput = nil
            }
            
            // Enable using AirPods as a high-quality lapel microphone.
            session.configuresApplicationAudioSessionForBluetoothHighQualityRecording = true
            
            if session.canSetSessionPreset(preset) {
                session.sessionPreset = preset
            }
            
            videoInput = try addInput(for: defaultCamera)
            audioInput = try addInput(for: defaultMic)
            
            observeDeviceChanges(defaultCamera)
            
            // Movie output
            try addOutput(movieOutput)
            
            if let connection = movieOutput.connection(with: .video), connection.isVideoStabilizationSupported {
                connection.preferredVideoStabilizationMode = .auto
            }

            setupState = .ready
        } catch {
            throw error
        }
    }

    func startRunning() {
        if !session.isRunning {
            session.startRunning()
        }
    }

    func stopRunning() {
        if session.isRunning {
            session.stopRunning()
            
            do {
                if currentDevice.isTorchModeSupported(.off) {
                    try currentDevice.lockForConfiguration()
                    
                    currentDevice.torchMode = .off
                    setTorchMode(.off)
                    
                    currentDevice.unlockForConfiguration()
                }
            } catch {
                
            }
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
                DispatchQueue.main.asyncAfter(deadline: .now()) {
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
    
    func switchCamera() {
        Task {
            let devices = await deviceLookup.cameras
            
            // Find the index of the currently selected video device.
            let selectedIndex = devices.firstIndex(of: currentDevice) ?? 0
            // Get the next index.
            var nextIndex = selectedIndex + 1
            // Wrap around if the next index is invalid.
            if nextIndex == devices.endIndex {
                nextIndex = 0
            }
            
            let nextDevice = devices[nextIndex]
            // Change the session's active capture device.
            changeCaptureDevice(to: nextDevice)
            
            // The app only calls this method in response to the user requesting to switch cameras.
            // Set the new selection as the user's preferred camera.
            AVCaptureDevice.userPreferredCamera = nextDevice
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
    
    @discardableResult
    func addInput(for device: AVCaptureDevice) throws -> AVCaptureDeviceInput {
        let input = try AVCaptureDeviceInput(device: device)
        
        guard session.canAddInput(input) else {
            throw CameraError.addInputFailed
        }
        
        session.addInput(input)
        
        return input
    }
    
    func addOutput(_ output: AVCaptureOutput) throws {
        guard session.canAddOutput(output) else {
            throw CameraError.addOutputFailed
        }
        
        session.addOutput(output)
    }
    
    func changeCaptureDevice(to device: AVCaptureDevice) {
        // The service must have a valid video input prior to calling this method.
        guard let currentInput = videoInput else {
            fatalError()
        }
        
        // Bracket the following configuration in a begin/commit configuration pair.
        session.beginConfiguration()
        defer {
            session.commitConfiguration()
        }
        
        // Remove the existing video input before attempting to connect a new one.
        session.removeInput(currentInput)
        
        do {
            // Attempt to connect a new input and device to the capture session.
            videoInput = try addInput(for: device)
            
            // Register for device observations.
            observeDeviceChanges(device)
        } catch {
            // Reconnect the existing camera on failure.
            session.addInput(currentInput)
        }
    }
    
    func observeDeviceChanges(_ device: AVCaptureDevice) {
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
    
    func reassertTorchIfNeeded() {
        guard wantsTorchOn else { return }
        guard currentDevice.hasTorch, currentDevice.isTorchAvailable, currentDevice.isTorchModeSupported(.on) else { return }

        do {
            try currentDevice.lockForConfiguration()
            defer { currentDevice.unlockForConfiguration() }
            if currentDevice.torchMode != .on {
                try? currentDevice.setTorchModeOn(level: AVCaptureDevice.maxAvailableTorchLevel)
                setTorchMode(.on)
            }
        } catch {
            print("Error reasserting torch: \(error)")
        }
    }
}
