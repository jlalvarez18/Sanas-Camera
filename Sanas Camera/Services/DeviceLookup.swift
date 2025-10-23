//
//  DeviceLookup.swift
//  Sanas Camera
//
//  Created by Juan Alvarez on 10/22/25.
//

internal import AVFoundation
import Combine

actor DeviceLookup {
    private let frontCameraSession: AVCaptureDevice.DiscoverySession
    private let backCameraSession: AVCaptureDevice.DiscoverySession
    
    init() {
        backCameraSession = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInDualCamera, .builtInWideAngleCamera], mediaType: .video, position: .back)
        frontCameraSession = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInTrueDepthCamera, .builtInWideAngleCamera], mediaType: .video, position: .front)
        
        // if the user doesn't define a preferred camera, we set it to the back camera
        if AVCaptureDevice.systemPreferredCamera == nil {
            AVCaptureDevice.userPreferredCamera = backCameraSession.devices.first
        }
    }
    
    /// Returns the system-preferred camera for the host system.
    var defaultCamera: AVCaptureDevice {
        get throws {
            guard let videoDevice = AVCaptureDevice.systemPreferredCamera else {
                throw CameraError.videoDeviceUnavailable
            }
            return videoDevice
        }
    }
    
    /// Returns the default microphone for the device on which the app runs.
    var defaultMic: AVCaptureDevice {
        get throws {
            guard let audioDevice = AVCaptureDevice.default(for: .audio) else {
                throw CameraError.audioDeviceUnavailable
            }
            return audioDevice
        }
    }
    
    var cameras: [AVCaptureDevice] {
        // Populate the cameras array with the available cameras.
        var cameras: [AVCaptureDevice] = []
        if let backCamera = backCameraSession.devices.first {
            cameras.append(backCamera)
        }
        if let frontCamera = frontCameraSession.devices.first {
            cameras.append(frontCamera)
        }
        
#if !targetEnvironment(simulator)
        if cameras.isEmpty {
            fatalError("No camera devices are found on this system.")
        }
#endif
        return cameras
    }
}
