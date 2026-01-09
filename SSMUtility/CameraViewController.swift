/*
See LICENSE folder for this sample’s licensing information.

Abstract:
The app's primary view controller that presents the camera interface.
*/

import UIKit
import AVFoundation
import SwiftUI

class CameraViewController: UIViewController {
    
    private var spinner: UIActivityIndicatorView!
    
    var windowOrientation: UIInterfaceOrientation {
        return view.window?.windowScene?.interfaceOrientation ?? .unknown
    }
	
    // MARK: - Feature Selection UI
    
    private var featureSelectionView: UIView!
    private var featureButtons: [FacialFeature: UIButton] = [:]
    private var allButton: UIButton!
    
    // MARK: - Orientation Warning
    
    private var orientationWarningView: UIView?
    
    // MARK: - Gallery Button
    
    private var galleryButton: UIButton!

    // MARK: View Controller Life Cycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Disable the UI. Enable the UI later, if and only if the session starts running.
        cameraButton.isEnabled = false
        photoButton.isEnabled = false
        
        // Set up the video preview view.
        previewView.session = session
		
        // Set up feature selection UI
        setupFeatureSelectionUI()
        setupGalleryButton()
        
        // Set up orientation monitoring
        setupOrientationMonitoring()
        
        // Check the video authorization status. Video access is required.
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            // The user has previously granted access to the camera.
            break
            
        case .notDetermined:
            /*
             The user has not yet been presented with the option to grant
             video access. Suspend the session queue to delay session
             setup until the access request has completed.
             */
            sessionQueue.suspend()
            AVCaptureDevice.requestAccess(for: .video, completionHandler: { granted in
                if !granted {
                    self.setupResult = .notAuthorized
                }
                self.sessionQueue.resume()
            })
            
        default:
            // The user has previously denied access.
            setupResult = .notAuthorized
        }
        
        /*
         Setup the capture session.
         In general, it's not safe to mutate an AVCaptureSession or any of its
         inputs, outputs, or connections from multiple threads at the same time.
         
         Don't perform these tasks on the main queue because
         AVCaptureSession.startRunning() is a blocking call, which can
         take a long time. Dispatch session setup to the sessionQueue, so
         that the main queue isn't blocked, which keeps the UI responsive.
         */
        sessionQueue.async {
            self.configureSession()
        }
        DispatchQueue.main.async {
            self.spinner = UIActivityIndicatorView(style: .large)
            self.spinner.color = UIColor.yellow
            self.previewView.addSubview(self.spinner)
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        // Refresh gallery badge when returning to this view (after gallery dismiss)
        updateGalleryBadge()
        
        sessionQueue.async {
            switch self.setupResult {
            case .success:
                // Only setup observers and start the session if setup succeeded.
                self.addObservers()
                self.session.startRunning()
                self.isSessionRunning = self.session.isRunning
                
                DispatchQueue.main.async {
                    // Ensure camera unavailable label is hidden
                    self.cameraUnavailableLabel.isHidden = true
                }
                
            case .notAuthorized:
                DispatchQueue.main.async {
                    // Show the camera unavailable label
                    self.cameraUnavailableLabel.isHidden = false
                    self.featureSelectionView.isHidden = true
                    
                    let changePrivacySetting = "Unmask Lab doesn't have permission to use the camera, please change privacy settings"
                    let message = NSLocalizedString(changePrivacySetting, comment: "Alert message when the user has denied access to the camera")
                    let alertController = UIAlertController(title: "Unmask Lab", message: message, preferredStyle: .alert)
                    
                    alertController.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"),
                                                            style: .cancel,
                                                            handler: nil))
                    
                    alertController.addAction(UIAlertAction(title: NSLocalizedString("Settings", comment: "Alert button to open Settings"),
                                                            style: .`default`,
                                                            handler: { _ in
                                                                UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!,
                                                                                          options: [:],
                                                                                          completionHandler: nil)
                    }))
                    
                    self.present(alertController, animated: true, completion: nil)
                }
                
            case .configurationFailed:
                DispatchQueue.main.async {
                    // Show the camera unavailable label
                    self.cameraUnavailableLabel.isHidden = false
                    self.featureSelectionView.isHidden = true
                    
                    let alertMsg = "Alert message when something goes wrong during capture session configuration"
                    let message = NSLocalizedString("Unable to capture media", comment: alertMsg)
                    let alertController = UIAlertController(title: "Unmask Lab", message: message, preferredStyle: .alert)
                    
                    alertController.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"),
                                                            style: .cancel,
                                                            handler: nil))
                    
                    self.present(alertController, animated: true, completion: nil)
                }
            }
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        sessionQueue.async {
            if self.setupResult == .success {
                self.session.stopRunning()
                self.isSessionRunning = self.session.isRunning
                self.removeObservers()
            }
        }
        
        // Stop orientation monitoring
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
        NotificationCenter.default.removeObserver(self, name: UIDevice.orientationDidChangeNotification, object: nil)
        
        super.viewWillDisappear(animated)
    }
    
   
    
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .portrait
    }
    
    // MARK: Session Management
    
    private enum SessionSetupResult {
        case success
        case notAuthorized
        case configurationFailed
    }
    
    private let session = AVCaptureSession()
    private var isSessionRunning = false
    private var selectedSemanticSegmentationMatteTypes = [AVSemanticSegmentationMatte.MatteType]()
    
    // Communicate with the session and other session objects on this queue.
    private let sessionQueue = DispatchQueue(label: "session queue")
    
    private var setupResult: SessionSetupResult = .success
    
    @objc dynamic var videoDeviceInput: AVCaptureDeviceInput!
    
    @IBOutlet private weak var previewView: PreviewView!
    
    // Call this on the session queue.
    /// - Tag: ConfigureSession
    private func configureSession() {
        if setupResult != .success {
            return
        }
        
        session.beginConfiguration()
        
        /*
         Do not create an AVCaptureMovieFileOutput when setting up the session because
         Live Photo is not supported when AVCaptureMovieFileOutput is added to the session.
         */
        session.sessionPreset = .photo
        
        // Add video input.
        do {
            var defaultVideoDevice: AVCaptureDevice?
            
            // Choose the back dual camera, if available, otherwise default to a wide angle camera.
            
            if let dualCameraDevice = AVCaptureDevice.default(.builtInDualCamera, for: .video, position: .back) {
                defaultVideoDevice = dualCameraDevice
            } else if let dualWideCameraDevice = AVCaptureDevice.default(.builtInDualWideCamera, for: .video, position: .back) {
                // If a rear dual camera is not available, default to the rear dual wide camera.
                defaultVideoDevice = dualWideCameraDevice
            } else if let backCameraDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) {
                // If a rear dual wide camera is not available, default to the rear wide angle camera.
                defaultVideoDevice = backCameraDevice
            } else if let frontCameraDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) {
                // If the rear wide angle camera isn't available, default to the front wide angle camera.
                defaultVideoDevice = frontCameraDevice
            }
            guard let videoDevice = defaultVideoDevice else {
                print("Default video device is unavailable.")
                setupResult = .configurationFailed
                session.commitConfiguration()
                return
            }
            let videoDeviceInput = try AVCaptureDeviceInput(device: videoDevice)
            
            if session.canAddInput(videoDeviceInput) {
                session.addInput(videoDeviceInput)
                self.videoDeviceInput = videoDeviceInput
                
                DispatchQueue.main.async {
                    /*
                     Dispatch video streaming to the main queue because AVCaptureVideoPreviewLayer is the backing layer for PreviewView.
                     You can manipulate UIView only on the main thread.
                     Note: As an exception to the above rule, it's not necessary to serialize video orientation changes
                     on the AVCaptureVideoPreviewLayer’s connection with other session manipulation.
                     */
                    var initialVideoOrientation: AVCaptureVideoOrientation = .portrait
                    if self.windowOrientation != .unknown {
                        if let videoOrientation = AVCaptureVideoOrientation(interfaceOrientation: self.windowOrientation) {
                            initialVideoOrientation = videoOrientation
                        }
                    }
                    
                    self.previewView.videoPreviewLayer.connection?.videoOrientation = initialVideoOrientation
                }
            } else {
                print("Couldn't add video device input to the session.")
                setupResult = .configurationFailed
                session.commitConfiguration()
                return
            }
        } catch {
            print("Couldn't create video device input: \(error)")
            setupResult = .configurationFailed
            session.commitConfiguration()
            return
        }
        
        // Add the photo output.
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
            
            photoOutput.isHighResolutionCaptureEnabled = true
            photoOutput.isLivePhotoCaptureEnabled = photoOutput.isLivePhotoCaptureSupported
            photoOutput.isDepthDataDeliveryEnabled = photoOutput.isDepthDataDeliverySupported
            photoOutput.isPortraitEffectsMatteDeliveryEnabled = photoOutput.isPortraitEffectsMatteDeliverySupported
            photoOutput.enabledSemanticSegmentationMatteTypes = photoOutput.availableSemanticSegmentationMatteTypes
            selectedSemanticSegmentationMatteTypes = photoOutput.availableSemanticSegmentationMatteTypes
            photoOutput.maxPhotoQualityPrioritization = .quality
            depthDataDeliveryMode = photoOutput.isDepthDataDeliverySupported ? .on : .off
            
        } else {
            print("Could not add photo output to the session")
            setupResult = .configurationFailed
            session.commitConfiguration()
            return
        }
        
        session.commitConfiguration()
    }
    
    // MARK: Device Configuration
    
    @IBOutlet private weak var cameraButton: UIButton!
    
    @IBOutlet private weak var cameraUnavailableLabel: UILabel!
    
    private let videoDeviceDiscoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .builtInDualCamera, .builtInTrueDepthCamera, .builtInDualWideCamera],
                                                                               mediaType: .video, position: .unspecified)

    /// - Tag: ChangeCamera
    @IBAction private func changeCamera(_ cameraButton: UIButton) {
        cameraButton.isEnabled = false
        photoButton.isEnabled = false
        
        sessionQueue.async {
            let currentVideoDevice = self.videoDeviceInput.device
            let currentPosition = currentVideoDevice.position

            let backVideoDeviceDiscoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInDualCamera, .builtInDualWideCamera, .builtInWideAngleCamera],
                                                                                   mediaType: .video, position: .back)
            let frontVideoDeviceDiscoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInTrueDepthCamera, .builtInWideAngleCamera],
                                                                                    mediaType: .video, position: .front)
            var newVideoDevice: AVCaptureDevice? = nil
            
            switch currentPosition {
            case .unspecified, .front:
                newVideoDevice = backVideoDeviceDiscoverySession.devices.first
                
            case .back:
                newVideoDevice = frontVideoDeviceDiscoverySession.devices.first
                
            @unknown default:
                print("Unknown capture position. Defaulting to back, dual-camera.")
                newVideoDevice = AVCaptureDevice.default(.builtInDualCamera, for: .video, position: .back)
            }
            
            if let videoDevice = newVideoDevice {
                do {
                    let videoDeviceInput = try AVCaptureDeviceInput(device: videoDevice)
                    
                    self.session.beginConfiguration()
                    
                    // Remove the existing device input first, because AVCaptureSession doesn't support
                    // simultaneous use of the rear and front cameras.
                    self.session.removeInput(self.videoDeviceInput)
                    
                    if self.session.canAddInput(videoDeviceInput) {
                        NotificationCenter.default.removeObserver(self, name: .AVCaptureDeviceSubjectAreaDidChange, object: currentVideoDevice)
                      
                        
                        self.session.addInput(videoDeviceInput)
                        self.videoDeviceInput = videoDeviceInput
                    } else {
                        self.session.addInput(self.videoDeviceInput)
                    }

                    
                    /*
                     Set Live Photo capture and depth data delivery if it's supported. When changing cameras, the
                     `livePhotoCaptureEnabled` and `depthDataDeliveryEnabled` properties of the AVCapturePhotoOutput
                     get set to false when a video device is disconnected from the session. After the new video device is
                     added to the session, re-enable them on the AVCapturePhotoOutput, if supported.
                     */
                    self.photoOutput.isLivePhotoCaptureEnabled = self.photoOutput.isLivePhotoCaptureSupported
                    self.photoOutput.isDepthDataDeliveryEnabled = self.photoOutput.isDepthDataDeliverySupported
                    self.photoOutput.isPortraitEffectsMatteDeliveryEnabled = self.photoOutput.isPortraitEffectsMatteDeliverySupported
                    self.photoOutput.enabledSemanticSegmentationMatteTypes = self.photoOutput.availableSemanticSegmentationMatteTypes
                    self.selectedSemanticSegmentationMatteTypes = self.photoOutput.availableSemanticSegmentationMatteTypes
                    self.photoOutput.maxPhotoQualityPrioritization = .quality
                    
                    self.session.commitConfiguration()
                } catch {
                    print("Error occurred while creating video device input: \(error)")
                }
            }
            
            DispatchQueue.main.async {
                self.cameraButton.isEnabled = true
                self.photoButton.isEnabled = true
            }
        }
    }

    
    // MARK: Capturing Photos
    
    private let photoOutput = AVCapturePhotoOutput()
    
    private var inProgressPhotoCaptureDelegates = [Int64: PhotoCaptureProcessor]()
    
    @IBOutlet private weak var photoButton: UIButton!
    
    /// - Tag: CapturePhoto
    @IBAction private func capturePhoto(_ photoButton: UIButton) {
        /*
         Retrieve the video preview layer's video orientation on the main queue before
         entering the session queue. Do this to ensure that UI elements are accessed on
         the main thread and session configuration is done on the session queue.
         */
        let videoPreviewLayerOrientation = previewView.videoPreviewLayer.connection?.videoOrientation
        
        sessionQueue.async {
            if let photoOutputConnection = self.photoOutput.connection(with: .video) {
                photoOutputConnection.videoOrientation = videoPreviewLayerOrientation!
            }
            var photoSettings = AVCapturePhotoSettings()
            
            // Capture HEIF photos when supported. Enable auto-flash and high-resolution photos.
            if  self.photoOutput.availablePhotoCodecTypes.contains(.hevc) {
                photoSettings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
            }
            
            if self.videoDeviceInput.device.isFlashAvailable {
                photoSettings.flashMode = .auto
            }
            
            photoSettings.isHighResolutionPhotoEnabled = true
            if let previewPhotoPixelFormatType = photoSettings.availablePreviewPhotoPixelFormatTypes.first {
                photoSettings.previewPhotoFormat = [kCVPixelBufferPixelFormatTypeKey as String: previewPhotoPixelFormatType]
            }
            
            photoSettings.isDepthDataDeliveryEnabled = (self.depthDataDeliveryMode == .on
                && self.photoOutput.isDepthDataDeliveryEnabled)
            
            if photoSettings.isDepthDataDeliveryEnabled {
                if !self.photoOutput.availableSemanticSegmentationMatteTypes.isEmpty {
                    photoSettings.enabledSemanticSegmentationMatteTypes = self.selectedSemanticSegmentationMatteTypes
                }
            }
            
            photoSettings.photoQualityPrioritization = .balanced
            
            let photoCaptureProcessor = PhotoCaptureProcessor(with: photoSettings, willCapturePhotoAnimation: {
                // Flash the screen to signal that a photo was taken.
                DispatchQueue.main.async {
                    self.previewView.videoPreviewLayer.opacity = 0
                    UIView.animate(withDuration: 0.25) {
                        self.previewView.videoPreviewLayer.opacity = 1
                    }
                }
            }, livePhotoCaptureHandler: { capturing in
               
            }, completionHandler: { photoCaptureProcessor in
                // When the capture is complete, remove a reference to the photo capture delegate so it can be deallocated.
                self.sessionQueue.async {
                    self.inProgressPhotoCaptureDelegates[photoCaptureProcessor.requestedPhotoSettings.uniqueID] = nil
                }
            }, photoProcessingHandler: { animate in
                // Animates a spinner while photo is processing
                DispatchQueue.main.async {
                    if animate {
                        self.spinner.hidesWhenStopped = true
                        self.spinner.center = CGPoint(x: self.previewView.frame.size.width / 2.0, y: self.previewView.frame.size.height / 2.0)
                        self.spinner.startAnimating()
                    } else {
                        self.spinner.stopAnimating()
                    }
                }
            }, photoSavedHandler: { savedCount, error in
                DispatchQueue.main.async {
                    self.showPhotoSavedAlert(savedCount: savedCount, error: error)
                }
            }
            )
            
            // The photo output holds a weak reference to the photo capture delegate and stores it in an array to maintain a strong reference.
            self.inProgressPhotoCaptureDelegates[photoCaptureProcessor.requestedPhotoSettings.uniqueID] = photoCaptureProcessor
            self.photoOutput.capturePhoto(with: photoSettings, delegate: photoCaptureProcessor)
        }
    }
    
    private enum DepthDataDeliveryMode {
        case on
        case off
    }
    
    private var depthDataDeliveryMode: DepthDataDeliveryMode = .off
    
    // MARK: KVO and Notifications
    
    private var keyValueObservations = [NSKeyValueObservation]()
    /// - Tag: ObserveInterruption
    private func addObservers() {
        let keyValueObservation = session.observe(\.isRunning, options: .new) { _, change in
            guard let isSessionRunning = change.newValue else { return }
            DispatchQueue.main.async {
                // Only enable the ability to change camera if the device has more than one camera.
                self.cameraButton.isEnabled = isSessionRunning && self.videoDeviceDiscoverySession.uniqueDevicePositionsCount > 1
                self.photoButton.isEnabled = isSessionRunning
            }
        }
        keyValueObservations.append(keyValueObservation)
    }
    
    private func removeObservers() {
        NotificationCenter.default.removeObserver(self)
        
        for keyValueObservation in keyValueObservations {
            keyValueObservation.invalidate()
        }
        keyValueObservations.removeAll()
    }
    
    // MARK: - Feature Selection UI Setup
    
    private func setupFeatureSelectionUI() {
        // Container view for feature buttons
        featureSelectionView = UIView()
        featureSelectionView.translatesAutoresizingMaskIntoConstraints = false
        featureSelectionView.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        featureSelectionView.layer.cornerRadius = 16
        view.addSubview(featureSelectionView)
        
        // Create horizontal stack view for buttons
        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.distribution = .fillEqually
        stackView.spacing = 8
        stackView.translatesAutoresizingMaskIntoConstraints = false
        featureSelectionView.addSubview(stackView)
        
        // Create "All" button
        allButton = createFeatureButton(title: "All", icon: "checkmark.circle.fill")
        allButton.addTarget(self, action: #selector(allButtonTapped), for: .touchUpInside)
        stackView.addArrangedSubview(allButton)
        
        // Create individual feature buttons
        for feature in FacialFeature.allCases {
            let button = createFeatureButton(title: feature.rawValue, icon: feature.icon)
            button.tag = FacialFeature.allCases.firstIndex(of: feature)!
            button.addTarget(self, action: #selector(featureButtonTapped(_:)), for: .touchUpInside)
            featureButtons[feature] = button
            stackView.addArrangedSubview(button)
        }
        
        // Layout constraints - overlay on top of camera preview
        NSLayoutConstraint.activate([
            featureSelectionView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            featureSelectionView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            featureSelectionView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            featureSelectionView.heightAnchor.constraint(equalToConstant: 70),
            
            stackView.leadingAnchor.constraint(equalTo: featureSelectionView.leadingAnchor, constant: 8),
            stackView.trailingAnchor.constraint(equalTo: featureSelectionView.trailingAnchor, constant: -8),
            stackView.topAnchor.constraint(equalTo: featureSelectionView.topAnchor, constant: 8),
            stackView.bottomAnchor.constraint(equalTo: featureSelectionView.bottomAnchor, constant: -8)
        ])
        
        // Update initial button states
        updateFeatureButtonStates()
    }
    
    private func createFeatureButton(title: String, icon: String) -> UIButton {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        
        var config = UIButton.Configuration.filled()
        config.title = title
        config.image = UIImage(systemName: icon)
        config.imagePlacement = .top
        config.imagePadding = 4
        config.cornerStyle = .medium
        config.baseBackgroundColor = UIColor.darkGray
        config.baseForegroundColor = .white
        
        // Smaller font for compact display
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = UIFont.systemFont(ofSize: 10, weight: .medium)
            return outgoing
        }
        
        button.configuration = config
        return button
    }
    
    @objc private func allButtonTapped() {
        Helper.sharedInstance.selectAllFeatures()
        updateFeatureButtonStates()
        
        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }
    
    @objc private func featureButtonTapped(_ sender: UIButton) {
        let feature = FacialFeature.allCases[sender.tag]
        Helper.sharedInstance.toggleFeature(feature)
        updateFeatureButtonStates()
        
        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }
    
    private func updateFeatureButtonStates() {
        let helper = Helper.sharedInstance
        
        // Update "All" button
        updateButtonAppearance(allButton, isSelected: helper.areAllFeaturesSelected)
        
        // Update individual feature buttons
        for feature in FacialFeature.allCases {
            if let button = featureButtons[feature] {
                updateButtonAppearance(button, isSelected: helper.isFeatureSelected(feature))
            }
        }
        
        // Update selected segmentation types for capture
        updateSelectedSegmentationTypes()
    }
    
    private func updateButtonAppearance(_ button: UIButton, isSelected: Bool) {
        var config = button.configuration
        if isSelected {
            config?.baseBackgroundColor = UIColor.systemYellow
            config?.baseForegroundColor = .black
        } else {
            config?.baseBackgroundColor = UIColor.darkGray.withAlphaComponent(0.8)
            config?.baseForegroundColor = .white.withAlphaComponent(0.6)
        }
        button.configuration = config
    }
    
    private func updateSelectedSegmentationTypes() {
        let helper = Helper.sharedInstance
        
        sessionQueue.async {
            // Filter available types based on user selection
            let availableTypes = self.photoOutput.availableSemanticSegmentationMatteTypes
            self.selectedSemanticSegmentationMatteTypes = availableTypes.filter { type in
                helper.selectedMatteTypes.contains(type)
            }
        }
    }
    
    // MARK: - Gallery Button
    
    private func setupGalleryButton() {
        galleryButton = UIButton(type: .system)
        galleryButton.translatesAutoresizingMaskIntoConstraints = false
        
        var config = UIButton.Configuration.filled()
        // Use larger SF Symbol to match capture icon size
        let largeConfig = UIImage.SymbolConfiguration(pointSize: 28, weight: .medium)
        config.image = UIImage(systemName: "photo.stack", withConfiguration: largeConfig)
        config.cornerStyle = .capsule
        config.baseBackgroundColor = UIColor.black.withAlphaComponent(0.6)
        config.baseForegroundColor = .systemYellow
        config.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)
        
        galleryButton.configuration = config
        galleryButton.addTarget(self, action: #selector(openGallery), for: .touchUpInside)
        
        view.addSubview(galleryButton)
        
        // Align with photo button (centered at bottom) and camera button (right side)
        // Photo button: 60x60, 40px from bottom, centered
        // Camera button: 60x60, 30px from trailing, aligned with photo button
        // Gallery button: 60x60, 30px from leading, aligned with photo button
        NSLayoutConstraint.activate([
            galleryButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 30),
            galleryButton.centerYAnchor.constraint(equalTo: photoButton.centerYAnchor),
            galleryButton.widthAnchor.constraint(equalToConstant: 60),
            galleryButton.heightAnchor.constraint(equalToConstant: 60)
        ])
        
        // Show image count badge
        updateGalleryBadge()
    }
    
    private func updateGalleryBadge() {
        let count = ImageStorageManager.shared.getImageCount()
        if count > 0 {
            // Add or update badge
            let badgeTag = 999
            if let existingBadge = galleryButton.viewWithTag(badgeTag) {
                if let label = existingBadge.subviews.first as? UILabel {
                    label.text = count > 99 ? "99+" : "\(count)"
                }
            } else {
                let badgeView = UIView()
                badgeView.tag = badgeTag
                badgeView.backgroundColor = .systemYellow
                badgeView.translatesAutoresizingMaskIntoConstraints = false
                badgeView.layer.cornerRadius = 10
                
                let badgeLabel = UILabel()
                badgeLabel.text = count > 99 ? "99+" : "\(count)"
                badgeLabel.font = .systemFont(ofSize: 10, weight: .bold)
                badgeLabel.textColor = .black
                badgeLabel.translatesAutoresizingMaskIntoConstraints = false
                
                badgeView.addSubview(badgeLabel)
                galleryButton.addSubview(badgeView)
                
                NSLayoutConstraint.activate([
                    badgeLabel.centerXAnchor.constraint(equalTo: badgeView.centerXAnchor),
                    badgeLabel.centerYAnchor.constraint(equalTo: badgeView.centerYAnchor),
                    
                    badgeView.topAnchor.constraint(equalTo: galleryButton.topAnchor, constant: -4),
                    badgeView.trailingAnchor.constraint(equalTo: galleryButton.trailingAnchor, constant: 4),
                    badgeView.widthAnchor.constraint(greaterThanOrEqualToConstant: 20),
                    badgeView.heightAnchor.constraint(equalToConstant: 20)
                ])
                
                badgeLabel.setContentHuggingPriority(.required, for: .horizontal)
            }
        } else {
            // Remove badge if no images
            if let badge = galleryButton.viewWithTag(999) {
                badge.removeFromSuperview()
            }
        }
    }
    
    @objc private func openGallery() {
        let galleryView = GalleryView()
        let hostingController = UIHostingController(rootView: galleryView)
        hostingController.modalPresentationStyle = .fullScreen
        present(hostingController, animated: true)
    }
    
    // MARK: - Orientation Monitoring
    
    private func setupOrientationMonitoring() {
        // Enable device orientation notifications
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(deviceOrientationDidChange),
            name: UIDevice.orientationDidChangeNotification,
            object: nil
        )
        
        // Check initial orientation
        checkDeviceOrientation()
    }
    
    @objc private func deviceOrientationDidChange() {
        checkDeviceOrientation()
    }
    
    private func checkDeviceOrientation() {
        let orientation = UIDevice.current.orientation
        
        if orientation.isLandscape {
            showOrientationWarning()
        } else if orientation.isPortrait {
            hideOrientationWarning()
        }
        // Ignore .faceUp, .faceDown, .unknown - keep current state
    }
    
    private func showOrientationWarning() {
        guard orientationWarningView == nil else { return }
        
        // Create overlay
        let overlay = UIView()
        overlay.backgroundColor = UIColor.black.withAlphaComponent(0.85)
        overlay.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(overlay)
        
        // Create content stack
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.spacing = 16
        stackView.translatesAutoresizingMaskIntoConstraints = false
        overlay.addSubview(stackView)
        
        // Rotation icon - SF Symbol with gold tint
        let iconImageView = UIImageView()
        let iconConfig = UIImage.SymbolConfiguration(pointSize: 60, weight: .medium)
        iconImageView.image = UIImage(systemName: "iphone.gen3", withConfiguration: iconConfig)
        iconImageView.tintColor = .systemYellow
        iconImageView.contentMode = .scaleAspectFit
        stackView.addArrangedSubview(iconImageView)
        
        // Add rotation animation to icon
        let rotationAnimation = CABasicAnimation(keyPath: "transform.rotation.z")
        rotationAnimation.fromValue = -CGFloat.pi / 4
        rotationAnimation.toValue = 0
        rotationAnimation.duration = 0.6
        rotationAnimation.autoreverses = true
        rotationAnimation.repeatCount = .infinity
        iconImageView.layer.add(rotationAnimation, forKey: "rotation")
        
        // Warning title
        let titleLabel = UILabel()
        titleLabel.text = "Rotate to Portrait"
        titleLabel.font = .systemFont(ofSize: 22, weight: .bold)
        titleLabel.textColor = .white
        stackView.addArrangedSubview(titleLabel)
        
        // Warning message
        let messageLabel = UILabel()
        messageLabel.text = "Please hold your device upright\nto capture photos"
        messageLabel.font = .systemFont(ofSize: 16)
        messageLabel.textColor = .white.withAlphaComponent(0.8)
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0
        stackView.addArrangedSubview(messageLabel)
        
        // Layout
        NSLayoutConstraint.activate([
            overlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            overlay.topAnchor.constraint(equalTo: view.topAnchor),
            overlay.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            stackView.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: overlay.centerYAnchor)
        ])
        
        // Animate in
        overlay.alpha = 0
        UIView.animate(withDuration: 0.3) {
            overlay.alpha = 1
        }
        
        orientationWarningView = overlay
        
        // Disable capture
        photoButton.isEnabled = false
    }
    
    private func hideOrientationWarning() {
        guard let overlay = orientationWarningView else { return }
        
        // Clear reference immediately to prevent duplicate calls
        orientationWarningView = nil
        
        UIView.animate(withDuration: 0.3, animations: {
            overlay.alpha = 0
        }) { _ in
            overlay.removeFromSuperview()
        }
        
        // Re-enable capture button
        photoButton.isEnabled = true
    }
    
    // MARK: - Photo Saved Alert
    
    private func showPhotoSavedAlert(savedCount: Int, error: Error?) {
        // Update gallery badge
        updateGalleryBadge()
        
        let alert: UIAlertController
        
        if let error = error {
            // Error alert
            alert = UIAlertController(
                title: "Save Failed",
                message: error.localizedDescription,
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
        } else {
            // Success alert
            let featureNames = Helper.sharedInstance.selectedFeatures.map { $0.rawValue }.joined(separator: ", ")
            let message: String
            
            if Helper.sharedInstance.selectedFeatures.isEmpty {
                message = "\(savedCount) photo saved to gallery."
            } else {
                message = "\(savedCount) photos saved: Original + \(featureNames)"
            }
            
            alert = UIAlertController(
                title: "✓ Saved!",
                message: message,
                preferredStyle: .alert
            )
            
            // Add action to view in gallery
            alert.addAction(UIAlertAction(title: "View Gallery", style: .default) { [weak self] _ in
                self?.openGallery()
            })
            alert.addAction(UIAlertAction(title: "OK", style: .cancel))
        }
        
        present(alert, animated: true)
    }
  
}

extension AVCaptureVideoOrientation {
    init?(deviceOrientation: UIDeviceOrientation) {
        switch deviceOrientation {
        case .portrait: self = .portrait
        case .portraitUpsideDown: self = .portraitUpsideDown
        case .landscapeLeft: self = .landscapeRight
        case .landscapeRight: self = .landscapeLeft
        default: return nil
        }
    }
    
    init?(interfaceOrientation: UIInterfaceOrientation) {
        switch interfaceOrientation {
        case .portrait: self = .portrait
        case .portraitUpsideDown: self = .portraitUpsideDown
        case .landscapeLeft: self = .landscapeLeft
        case .landscapeRight: self = .landscapeRight
        default: return nil
        }
    }
}

extension AVCaptureDevice.DiscoverySession {
    var uniqueDevicePositionsCount: Int {
        
        var uniqueDevicePositions = [AVCaptureDevice.Position]()
        
        for device in devices where !uniqueDevicePositions.contains(device.position) {
            uniqueDevicePositions.append(device.position)
        }
        
        return uniqueDevicePositions.count
    }
}
