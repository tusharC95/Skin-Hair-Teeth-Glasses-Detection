/*
 CameraViewModel.swift
 SSMUtility

 ViewModel for CameraViewController - manages camera state, photo capture,
 and coordinates between managers.
*/

import AVFoundation
import UIKit
import Sentry

private let logger = SentrySDK.logger

// MARK: - Callbacks

struct CameraViewModelCallbacks {
    var onSessionRunningChanged: ((Bool) -> Void)?
    var onSessionError: ((CameraSessionError) -> Void)?
    var onSessionStarted: (() -> Void)?
    var onOrientationChanged: ((Bool) -> Void)?
    var onPhotoCapturing: ((Bool) -> Void)?
    var onPhotoSaved: ((Int, Error?) -> Void)?
    var onGalleryCountChanged: ((Int) -> Void)?
}

// MARK: - CameraViewModel

class CameraViewModel {
    
    // MARK: - Properties
    
    private let sessionManager: CameraSessionManager
    private let orientationManager: OrientationManager
    
    var callbacks = CameraViewModelCallbacks()
    
    // State
    private(set) var isSessionRunning = false
    private(set) var isLandscape = false
    private(set) var selectedFeatures: Set<FacialFeature> = []
    private(set) var galleryImageCount = 0
    
    private var inProgressPhotoCaptureDelegates = [Int64: PhotoCaptureProcessor]()
    
    // Computed
    var canSwitchCamera: Bool {
        return sessionManager.canSwitchCamera
    }
    
    var isCaptureEnabled: Bool {
        return isSessionRunning && !isLandscape
    }
    
    var previewSession: AVCaptureSession {
        return sessionManager.session
    }
    
    var isDepthDataSupported: Bool {
        return sessionManager.isDepthDataDeliverySupported
    }
    
    // MARK: - Initialization
    
    init(sessionManager: CameraSessionManager = CameraSessionManager(),
         orientationManager: OrientationManager = OrientationManager()) {
        self.sessionManager = sessionManager
        self.orientationManager = orientationManager
        
        setupDelegates()
        loadInitialState()
    }
    
    private func setupDelegates() {
        sessionManager.delegate = self
        orientationManager.delegate = self
    }
    
    private func loadInitialState() {
        selectedFeatures = Helper.sharedInstance.selectedFeatures
        galleryImageCount = ImageStorageManager.shared.getImageCount()
    }
    
    // MARK: - Session Management
    
    func checkCameraAuthorization(completion: @escaping (Bool) -> Void) {
        sessionManager.checkAuthorization(completion: completion)
    }
    
    func configureSession() {
        sessionManager.configureSession()
    }
    
    func startSession() {
        sessionManager.startSession()
    }
    
    func stopSession() {
        sessionManager.stopSession()
    }
    
    // MARK: - Orientation Management
    
    func startOrientationMonitoring() {
        orientationManager.startMonitoring()
    }
    
    func stopOrientationMonitoring() {
        orientationManager.stopMonitoring()
    }
    
    // MARK: - Camera Control
    
    func switchCamera(completion: @escaping (Bool) -> Void) {
        sessionManager.switchCamera(completion: completion)
    }
    
    // MARK: - Feature Selection
    
    func selectAllFeatures() {
        Helper.sharedInstance.selectAllFeatures()
        selectedFeatures = Helper.sharedInstance.selectedFeatures
        logger.info("All features selected")
        updateSegmentationTypes()
    }
    
    func toggleFeature(_ feature: FacialFeature) {
        Helper.sharedInstance.toggleFeature(feature)
        selectedFeatures = Helper.sharedInstance.selectedFeatures
        let isSelected = selectedFeatures.contains(feature)
        logger.debug("Feature toggled", attributes: [
            "feature": feature.rawValue,
            "isSelected": isSelected
        ])
        updateSegmentationTypes()
    }
    
    var areAllFeaturesSelected: Bool {
        return Helper.sharedInstance.areAllFeaturesSelected
    }
    
    private func updateSegmentationTypes() {
        let matteTypes = Helper.sharedInstance.selectedMatteTypes
        sessionManager.updateSelectedSegmentationTypes(with: matteTypes)
    }
    
    // MARK: - Photo Capture
    
    func capturePhoto(previewLayer: AVCaptureVideoPreviewLayer) {
        let videoRotationAngle = previewLayer.connection?.videoRotationAngle ?? 90
        
        sessionManager.sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Configure photo output connection
            if let photoOutputConnection = self.sessionManager.photoOutput.connection(with: .video) {
                if photoOutputConnection.isVideoRotationAngleSupported(videoRotationAngle) {
                    photoOutputConnection.videoRotationAngle = videoRotationAngle
                }
            }
            
            // Create photo settings
            var photoSettings = AVCapturePhotoSettings()
            
            if self.sessionManager.photoOutput.availablePhotoCodecTypes.contains(.hevc) {
                photoSettings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
            }
            
            if self.sessionManager.videoDeviceInput.device.isFlashAvailable {
                photoSettings.flashMode = .auto
            }
            
            photoSettings.maxPhotoDimensions = self.sessionManager.photoOutput.maxPhotoDimensions
            
            if let previewFormat = photoSettings.availablePreviewPhotoPixelFormatTypes.first {
                photoSettings.previewPhotoFormat = [kCVPixelBufferPixelFormatTypeKey as String: previewFormat]
            }
            
            // Configure depth and segmentation
            let depthEnabled = self.isDepthDataSupported && self.sessionManager.photoOutput.isDepthDataDeliveryEnabled
            photoSettings.isDepthDataDeliveryEnabled = depthEnabled
            
            if depthEnabled && !self.sessionManager.photoOutput.availableSemanticSegmentationMatteTypes.isEmpty {
                photoSettings.enabledSemanticSegmentationMatteTypes = self.sessionManager.selectedSemanticSegmentationMatteTypes
            }
            
            photoSettings.photoQualityPrioritization = .balanced
            
            // Create capture processor
            let processor = PhotoCaptureProcessor(
                with: photoSettings,
                willCapturePhotoAnimation: { [weak self] in
                    // Notify for flash animation
                    DispatchQueue.main.async {
                        self?.callbacks.onPhotoCapturing?(true)
                    }
                },
                livePhotoCaptureHandler: { _ in },
                completionHandler: { [weak self] processor in
                    self?.sessionManager.sessionQueue.async {
                        self?.inProgressPhotoCaptureDelegates[processor.requestedPhotoSettings.uniqueID] = nil
                    }
                },
                photoProcessingHandler: { [weak self] isProcessing in
                    DispatchQueue.main.async {
                        self?.callbacks.onPhotoCapturing?(isProcessing)
                    }
                },
                photoSavedHandler: { [weak self] savedCount, error in
                    DispatchQueue.main.async {
                        self?.galleryImageCount = ImageStorageManager.shared.getImageCount()
                        self?.callbacks.onGalleryCountChanged?(self?.galleryImageCount ?? 0)
                        self?.callbacks.onPhotoSaved?(savedCount, error)
                    }
                }
            )
            
            self.inProgressPhotoCaptureDelegates[processor.requestedPhotoSettings.uniqueID] = processor
            self.sessionManager.photoOutput.capturePhoto(with: photoSettings, delegate: processor)
        }
    }
    
    // MARK: - Gallery
    
    func refreshGalleryCount() {
        galleryImageCount = ImageStorageManager.shared.getImageCount()
        callbacks.onGalleryCountChanged?(galleryImageCount)
    }
    
    // MARK: - Video Rotation
    
    func configurePreviewOrientation(previewLayer: AVCaptureVideoPreviewLayer, windowOrientation: UIInterfaceOrientation) {
        guard let connection = previewLayer.connection else { return }
        let rotationAngle = videoRotationAngle(for: windowOrientation)
        if connection.isVideoRotationAngleSupported(rotationAngle) {
            connection.videoRotationAngle = rotationAngle
        }
    }
    
    private func videoRotationAngle(for orientation: UIInterfaceOrientation) -> CGFloat {
        switch orientation {
        case .portrait: return 90
        case .portraitUpsideDown: return 270
        case .landscapeLeft: return 180
        case .landscapeRight: return 0
        default: return 90
        }
    }
}

// MARK: - CameraSessionManagerDelegate

extension CameraViewModel: CameraSessionManagerDelegate {
    func sessionManager(_ manager: CameraSessionManager, didChangeRunningState isRunning: Bool) {
        self.isSessionRunning = isRunning
        callbacks.onSessionRunningChanged?(isRunning)
    }
    
    func sessionManager(_ manager: CameraSessionManager, didFailWithError error: CameraSessionError) {
        callbacks.onSessionError?(error)
    }
    
    func sessionManagerDidStartSession(_ manager: CameraSessionManager) {
        callbacks.onSessionStarted?()
    }
}

// MARK: - OrientationManagerDelegate

extension CameraViewModel: OrientationManagerDelegate {
    func orientationManager(_ manager: OrientationManager, didChangeToLandscape isLandscape: Bool) {
        self.isLandscape = isLandscape
        callbacks.onOrientationChanged?(isLandscape)
    }
}
