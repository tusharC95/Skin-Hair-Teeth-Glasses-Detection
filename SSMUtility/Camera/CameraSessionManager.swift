/*
 CameraSessionManager.swift
 SSMUtility

 Handles AVCaptureSession configuration, photo capture, and device management.
*/

import AVFoundation
import UIKit
import Sentry

private let logger = SentrySDK.logger

// MARK: - Protocols

protocol CameraSessionManagerDelegate: AnyObject {
    func sessionManager(_ manager: CameraSessionManager, didChangeRunningState isRunning: Bool)
    func sessionManager(_ manager: CameraSessionManager, didFailWithError error: CameraSessionError)
    func sessionManagerDidStartSession(_ manager: CameraSessionManager)
}

// MARK: - Error Types

enum CameraSessionError: Error {
    case notAuthorized
    case configurationFailed
    case deviceUnavailable
    
    var localizedDescription: String {
        switch self {
        case .notAuthorized:
            return "Camera access not authorized"
        case .configurationFailed:
            return "Unable to configure camera session"
        case .deviceUnavailable:
            return "Camera device unavailable"
        }
    }
}

enum SessionSetupResult {
    case success
    case notAuthorized
    case configurationFailed
}

// MARK: - CameraSessionManager

class CameraSessionManager {
    
    // MARK: - Properties
    
    weak var delegate: CameraSessionManagerDelegate?
    
    let session = AVCaptureSession()
    let photoOutput = AVCapturePhotoOutput()
    
    private(set) var isSessionRunning = false
    private(set) var setupResult: SessionSetupResult = .success
    private(set) var videoDeviceInput: AVCaptureDeviceInput!
    private(set) var selectedSemanticSegmentationMatteTypes = [AVSemanticSegmentationMatte.MatteType]()
    
    let sessionQueue = DispatchQueue(label: "camera.session.queue")
    
    private var keyValueObservations = [NSKeyValueObservation]()
    
    private let videoDeviceDiscoverySession = AVCaptureDevice.DiscoverySession(
        deviceTypes: [.builtInWideAngleCamera, .builtInDualCamera, .builtInTrueDepthCamera, .builtInDualWideCamera],
        mediaType: .video,
        position: .unspecified
    )
    
    var canSwitchCamera: Bool {
        return videoDeviceDiscoverySession.uniqueDevicePositionsCount > 1
    }
    
    // MARK: - Authorization
    
    func checkAuthorization(completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            completion(true)
            
        case .notDetermined:
            sessionQueue.suspend()
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if !granted {
                    self?.setupResult = .notAuthorized
                }
                self?.sessionQueue.resume()
                completion(granted)
            }
            
        default:
            setupResult = .notAuthorized
            completion(false)
        }
    }
    
    // MARK: - Session Configuration
    
    func configureSession() {
        sessionQueue.async { [weak self] in
            self?.performSessionConfiguration()
        }
    }
    
    private func performSessionConfiguration() {
        guard setupResult == .success else { return }
        
        logger.info("Configuring camera session")
        
        session.beginConfiguration()
        session.sessionPreset = .photo
        
        // Add video input
        do {
            guard let videoDevice = selectVideoDevice() else {
                setupResult = .configurationFailed
                session.commitConfiguration()
                let error = CameraSessionError.deviceUnavailable
                SentryErrorReporter.shared.reportError(error, context: "CameraSessionManager.performSessionConfiguration")
                DispatchQueue.main.async {
                    self.delegate?.sessionManager(self, didFailWithError: .deviceUnavailable)
                }
                return
            }
            
            let videoDeviceInput = try AVCaptureDeviceInput(device: videoDevice)
            
            if session.canAddInput(videoDeviceInput) {
                session.addInput(videoDeviceInput)
                self.videoDeviceInput = videoDeviceInput
            } else {
                setupResult = .configurationFailed
                session.commitConfiguration()
                let error = CameraSessionError.configurationFailed
                SentryErrorReporter.shared.reportError(error, context: "CameraSessionManager.canAddInput")
                DispatchQueue.main.async {
                    self.delegate?.sessionManager(self, didFailWithError: .configurationFailed)
                }
                return
            }
        } catch {
            setupResult = .configurationFailed
            session.commitConfiguration()
            SentryErrorReporter.shared.reportError(error, context: "CameraSessionManager.AVCaptureDeviceInput")
            DispatchQueue.main.async {
                self.delegate?.sessionManager(self, didFailWithError: .configurationFailed)
            }
            return
        }
        
        // Add photo output
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
            configurePhotoOutput()
        } else {
            setupResult = .configurationFailed
            session.commitConfiguration()
            let error = CameraSessionError.configurationFailed
            SentryErrorReporter.shared.reportError(error, context: "CameraSessionManager.canAddOutput")
            logger.error("Failed to add photo output to session")
            DispatchQueue.main.async {
                self.delegate?.sessionManager(self, didFailWithError: .configurationFailed)
            }
            return
        }
        
        session.commitConfiguration()
        logger.info("Camera session configured successfully", attributes: [
            "sessionPreset": "photo",
            "depthDataSupported": photoOutput.isDepthDataDeliverySupported
        ])
    }
    
    private func selectVideoDevice() -> AVCaptureDevice? {
        if let dualCamera = AVCaptureDevice.default(.builtInDualCamera, for: .video, position: .back) {
            return dualCamera
        } else if let dualWideCamera = AVCaptureDevice.default(.builtInDualWideCamera, for: .video, position: .back) {
            return dualWideCamera
        } else if let backCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) {
            return backCamera
        } else if let frontCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) {
            return frontCamera
        }
        return nil
    }
    
    private func configurePhotoOutput() {
        photoOutput.maxPhotoDimensions = videoDeviceInput.device.activeFormat.supportedMaxPhotoDimensions.last ?? CMVideoDimensions(width: 4032, height: 3024)
        photoOutput.isLivePhotoCaptureEnabled = photoOutput.isLivePhotoCaptureSupported
        photoOutput.isDepthDataDeliveryEnabled = photoOutput.isDepthDataDeliverySupported
        photoOutput.isPortraitEffectsMatteDeliveryEnabled = photoOutput.isPortraitEffectsMatteDeliverySupported
        photoOutput.enabledSemanticSegmentationMatteTypes = photoOutput.availableSemanticSegmentationMatteTypes
        selectedSemanticSegmentationMatteTypes = photoOutput.availableSemanticSegmentationMatteTypes
        photoOutput.maxPhotoQualityPrioritization = .quality
    }
    
    // MARK: - Session Control
    
    func startSession() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            switch self.setupResult {
            case .success:
                self.addObservers()
                self.session.startRunning()
                self.isSessionRunning = self.session.isRunning
                logger.info("Camera session started")
                
                DispatchQueue.main.async {
                    self.delegate?.sessionManagerDidStartSession(self)
                }
                
            case .notAuthorized:
                DispatchQueue.main.async {
                    self.delegate?.sessionManager(self, didFailWithError: .notAuthorized)
                }
                
            case .configurationFailed:
                DispatchQueue.main.async {
                    self.delegate?.sessionManager(self, didFailWithError: .configurationFailed)
                }
            }
        }
    }
    
    func stopSession() {
        sessionQueue.async { [weak self] in
            guard let self = self, self.setupResult == .success else { return }
            self.session.stopRunning()
            self.isSessionRunning = self.session.isRunning
            self.removeObservers()
        }
    }
    
    // MARK: - Camera Switching
    
    func switchCamera(completion: @escaping (Bool) -> Void) {
        sessionQueue.async { [weak self] in
            guard let self = self else {
                DispatchQueue.main.async { completion(false) }
                return
            }
            
            let currentPosition = self.videoDeviceInput.device.position
            let newDevice = self.findAlternateCamera(for: currentPosition)
            
            guard let videoDevice = newDevice else {
                DispatchQueue.main.async { completion(false) }
                return
            }
            
            do {
                let newInput = try AVCaptureDeviceInput(device: videoDevice)
                
                self.session.beginConfiguration()
                
                // Remove existing input
                NotificationCenter.default.removeObserver(
                    self,
                    name: AVCaptureDevice.subjectAreaDidChangeNotification,
                    object: self.videoDeviceInput.device
                )
                self.session.removeInput(self.videoDeviceInput)
                
                // Add new input
                if self.session.canAddInput(newInput) {
                    self.session.addInput(newInput)
                    self.videoDeviceInput = newInput
                } else {
                    self.session.addInput(self.videoDeviceInput)
                }
                
                // Reconfigure photo output
                self.photoOutput.isLivePhotoCaptureEnabled = self.photoOutput.isLivePhotoCaptureSupported
                self.photoOutput.isDepthDataDeliveryEnabled = self.photoOutput.isDepthDataDeliverySupported
                self.photoOutput.isPortraitEffectsMatteDeliveryEnabled = self.photoOutput.isPortraitEffectsMatteDeliverySupported
                self.photoOutput.enabledSemanticSegmentationMatteTypes = self.photoOutput.availableSemanticSegmentationMatteTypes
                self.selectedSemanticSegmentationMatteTypes = self.photoOutput.availableSemanticSegmentationMatteTypes
                self.photoOutput.maxPhotoQualityPrioritization = .quality
                
                self.session.commitConfiguration()
                
                DispatchQueue.main.async { completion(true) }
            } catch {
                DispatchQueue.main.async {
                    self.delegate?.sessionManager(self, didFailWithError: .configurationFailed)
                    completion(false)
                }
            }
        }
    }
    
    private func findAlternateCamera(for currentPosition: AVCaptureDevice.Position) -> AVCaptureDevice? {
        let backDiscovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInDualCamera, .builtInDualWideCamera, .builtInWideAngleCamera],
            mediaType: .video,
            position: .back
        )
        let frontDiscovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInTrueDepthCamera, .builtInWideAngleCamera],
            mediaType: .video,
            position: .front
        )
        
        switch currentPosition {
        case .unspecified, .front:
            return backDiscovery.devices.first
        case .back:
            return frontDiscovery.devices.first
        @unknown default:
            return AVCaptureDevice.default(.builtInDualCamera, for: .video, position: .back)
        }
    }
    
    // MARK: - Segmentation Types
    
    func updateSelectedSegmentationTypes(with matteTypes: [AVSemanticSegmentationMatte.MatteType]) {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            let availableTypes = self.photoOutput.availableSemanticSegmentationMatteTypes
            self.selectedSemanticSegmentationMatteTypes = availableTypes.filter { matteTypes.contains($0) }
        }
    }
    
    // MARK: - Observers
    
    private func addObservers() {
        let observation = session.observe(\.isRunning, options: .new) { [weak self] _, change in
            guard let self = self, let isRunning = change.newValue else { return }
            DispatchQueue.main.async {
                self.delegate?.sessionManager(self, didChangeRunningState: isRunning)
            }
        }
        keyValueObservations.append(observation)
    }
    
    private func removeObservers() {
        NotificationCenter.default.removeObserver(self)
        keyValueObservations.forEach { $0.invalidate() }
        keyValueObservations.removeAll()
    }
    
    // MARK: - Depth Data
    
    var isDepthDataDeliverySupported: Bool {
        return photoOutput.isDepthDataDeliverySupported
    }
}
