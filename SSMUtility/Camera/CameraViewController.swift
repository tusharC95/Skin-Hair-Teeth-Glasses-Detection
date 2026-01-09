/*
 CameraViewController.swift
 SSMUtility

 View controller for camera interface - handles UI layout and user interactions.
 Business logic delegated to CameraViewModel.
*/

import UIKit
import AVFoundation
import SwiftUI

class CameraViewController: UIViewController {
    
    // MARK: - ViewModel
    
    private let viewModel = CameraViewModel()
    
    // MARK: - UI Elements
    
    private var previewView: PreviewView!
    private var cameraUnavailableLabel: UILabel!
    private var photoButton: UIButton!
    private var cameraButton: UIButton!
    private var galleryButton: UIButton!
    private var featureSelectionView: FeatureSelectionView!
    private var orientationWarningView: OrientationWarningView?
    private var spinner: UIActivityIndicatorView!
    
    // MARK: - Computed Properties
    
    private var windowOrientation: UIInterfaceOrientation {
        if let windowScene = view.window?.windowScene {
            return windowScene.effectiveGeometry.interfaceOrientation
        }
        return .unknown
    }
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupUI()
        setupBindings()
        configureInitialState()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        viewModel.refreshGalleryCount()
        viewModel.startOrientationMonitoring()
        viewModel.startSession()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        viewModel.stopSession()
        viewModel.stopOrientationMonitoring()
        super.viewWillDisappear(animated)
    }
    
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .portrait
    }
    
    // MARK: - Setup
    
    private func setupUI() {
        view.backgroundColor = .black
        
        setupPreviewView()
        setupCameraUnavailableLabel()
        setupPhotoButton()
        setupCameraButton()
        setupGalleryButton()
        setupFeatureSelectionView()
        setupSpinner()
        setupConstraints()
    }
    
    private func setupPreviewView() {
        previewView = PreviewView()
        previewView.translatesAutoresizingMaskIntoConstraints = false
        previewView.backgroundColor = .black
        previewView.session = viewModel.previewSession
        view.addSubview(previewView)
    }
    
    private func setupCameraUnavailableLabel() {
        cameraUnavailableLabel = UILabel()
        cameraUnavailableLabel.translatesAutoresizingMaskIntoConstraints = false
        cameraUnavailableLabel.text = "Camera Unavailable"
        cameraUnavailableLabel.textColor = .systemYellow
        cameraUnavailableLabel.font = .systemFont(ofSize: 24)
        cameraUnavailableLabel.textAlignment = .center
        cameraUnavailableLabel.numberOfLines = 0
        cameraUnavailableLabel.isHidden = true
        view.addSubview(cameraUnavailableLabel)
    }
    
    private func setupPhotoButton() {
        photoButton = UIButton(type: .custom)
        photoButton.translatesAutoresizingMaskIntoConstraints = false
        photoButton.setImage(UIImage(named: "CapturePhoto"), for: .normal)
        photoButton.tintColor = .systemYellow
        photoButton.contentMode = .scaleAspectFill
        photoButton.layer.cornerRadius = 4
        photoButton.isEnabled = false
        photoButton.addTarget(self, action: #selector(captureButtonTapped), for: .touchUpInside)
        view.addSubview(photoButton)
    }
    
    private func setupCameraButton() {
        cameraButton = UIButton(type: .custom)
        cameraButton.translatesAutoresizingMaskIntoConstraints = false
        cameraButton.setImage(UIImage(named: "FlipCamera"), for: .normal)
        cameraButton.tintColor = .systemYellow
        cameraButton.contentMode = .scaleAspectFill
        cameraButton.layer.cornerRadius = 4
        cameraButton.isEnabled = false
        cameraButton.addTarget(self, action: #selector(switchCameraButtonTapped), for: .touchUpInside)
        view.addSubview(cameraButton)
    }
    
    private func setupGalleryButton() {
        galleryButton = UIButton(type: .system)
        galleryButton.translatesAutoresizingMaskIntoConstraints = false
        
        var config = UIButton.Configuration.filled()
        let largeConfig = UIImage.SymbolConfiguration(pointSize: 28, weight: .medium)
        config.image = UIImage(systemName: "photo.stack", withConfiguration: largeConfig)
        config.cornerStyle = .capsule
        config.baseBackgroundColor = UIColor.black.withAlphaComponent(0.6)
        config.baseForegroundColor = .systemYellow
        config.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)
        
        galleryButton.configuration = config
        galleryButton.addTarget(self, action: #selector(galleryButtonTapped), for: .touchUpInside)
        view.addSubview(galleryButton)
    }
    
    private func setupFeatureSelectionView() {
        featureSelectionView = FeatureSelectionView()
        featureSelectionView.translatesAutoresizingMaskIntoConstraints = false
        featureSelectionView.delegate = self
        view.addSubview(featureSelectionView)
        
        updateFeatureSelectionState()
    }
    
    private func setupSpinner() {
        spinner = UIActivityIndicatorView(style: .large)
        spinner.color = .yellow
        spinner.hidesWhenStopped = true
        previewView.addSubview(spinner)
    }
    
    private func setupConstraints() {
        NSLayoutConstraint.activate([
            // Preview View
            previewView.topAnchor.constraint(equalTo: view.topAnchor),
            previewView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            previewView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            previewView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            // Camera Unavailable Label
            cameraUnavailableLabel.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor),
            cameraUnavailableLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            
            // Photo Button
            photoButton.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor),
            photoButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -40),
            photoButton.widthAnchor.constraint(equalToConstant: 60),
            photoButton.heightAnchor.constraint(equalToConstant: 60),
            
            // Camera Button
            cameraButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -30),
            cameraButton.centerYAnchor.constraint(equalTo: photoButton.centerYAnchor),
            cameraButton.widthAnchor.constraint(equalToConstant: 60),
            cameraButton.heightAnchor.constraint(equalToConstant: 60),
            
            // Gallery Button
            galleryButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 30),
            galleryButton.centerYAnchor.constraint(equalTo: photoButton.centerYAnchor),
            galleryButton.widthAnchor.constraint(equalToConstant: 60),
            galleryButton.heightAnchor.constraint(equalToConstant: 60),
            
            // Feature Selection View
            featureSelectionView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            featureSelectionView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            featureSelectionView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            featureSelectionView.heightAnchor.constraint(equalToConstant: 70)
        ])
    }
    
    // MARK: - Bindings
    
    private func setupBindings() {
        viewModel.callbacks.onSessionRunningChanged = { [weak self] isRunning in
            self?.updateControlsForSessionState(isRunning: isRunning)
        }
        
        viewModel.callbacks.onSessionError = { [weak self] error in
            self?.handleSessionError(error)
        }
        
        viewModel.callbacks.onSessionStarted = { [weak self] in
            self?.handleSessionStarted()
        }
        
        viewModel.callbacks.onOrientationChanged = { [weak self] isLandscape in
            self?.handleOrientationChange(isLandscape: isLandscape)
        }
        
        viewModel.callbacks.onPhotoCapturing = { [weak self] isCapturing in
            self?.handlePhotoCapturing(isCapturing: isCapturing)
        }
        
        viewModel.callbacks.onPhotoSaved = { [weak self] savedCount, error in
            self?.showPhotoSavedAlert(savedCount: savedCount, error: error)
        }
        
        viewModel.callbacks.onGalleryCountChanged = { [weak self] count in
            self?.updateGalleryBadge(count: count)
        }
    }
    
    private func configureInitialState() {
        viewModel.checkCameraAuthorization { [weak self] authorized in
            if authorized {
                self?.viewModel.configureSession()
            }
        }
    }
    
    // MARK: - Actions
    
    @objc private func captureButtonTapped() {
        viewModel.capturePhoto(previewLayer: previewView.videoPreviewLayer)
    }
    
    @objc private func switchCameraButtonTapped() {
        cameraButton.isEnabled = false
        photoButton.isEnabled = false
        
        viewModel.switchCamera { [weak self] success in
            guard let self = self else { return }
            self.cameraButton.isEnabled = self.viewModel.canSwitchCamera && self.viewModel.isSessionRunning
            self.photoButton.isEnabled = self.viewModel.isCaptureEnabled
        }
    }
    
    @objc private func galleryButtonTapped() {
        let galleryView = GalleryView()
        let hostingController = UIHostingController(rootView: galleryView)
        hostingController.modalPresentationStyle = .fullScreen
        present(hostingController, animated: true)
    }
    
    // MARK: - State Updates
    
    private func updateControlsForSessionState(isRunning: Bool) {
        cameraButton.isEnabled = isRunning && viewModel.canSwitchCamera
        photoButton.isEnabled = isRunning && !viewModel.isLandscape
    }
    
    private func handleSessionStarted() {
        cameraUnavailableLabel.isHidden = true
        viewModel.configurePreviewOrientation(previewLayer: previewView.videoPreviewLayer, windowOrientation: windowOrientation)
    }
    
    private func handleSessionError(_ error: CameraSessionError) {
        cameraUnavailableLabel.isHidden = false
        featureSelectionView.isHidden = true
        
        let message: String
        let title = "Unmask Lab"
        
        switch error {
        case .notAuthorized:
            message = "Unmask Lab doesn't have permission to use the camera, please change privacy settings"
            showAlertWithSettings(title: title, message: message)
        case .configurationFailed, .deviceUnavailable:
            message = "Unable to capture media"
            showAlert(title: title, message: message)
        }
    }
    
    private func handleOrientationChange(isLandscape: Bool) {
        if isLandscape {
            showOrientationWarning()
        } else {
            hideOrientationWarning()
        }
        photoButton.isEnabled = viewModel.isCaptureEnabled
    }
    
    private func handlePhotoCapturing(isCapturing: Bool) {
        if isCapturing {
            spinner.center = CGPoint(x: previewView.frame.size.width / 2.0, y: previewView.frame.size.height / 2.0)
            spinner.startAnimating()
            
            // Flash animation
            previewView.videoPreviewLayer.opacity = 0
            UIView.animate(withDuration: 0.25) {
                self.previewView.videoPreviewLayer.opacity = 1
            }
        } else {
            spinner.stopAnimating()
        }
    }
    
    // MARK: - Orientation Warning
    
    private func showOrientationWarning() {
        guard orientationWarningView == nil else { return }
        
        let warningView = OrientationWarningView()
        warningView.show(in: view)
        orientationWarningView = warningView
    }
    
    private func hideOrientationWarning() {
        orientationWarningView?.hide { [weak self] in
            self?.orientationWarningView = nil
        }
    }
    
    // MARK: - Gallery Badge
    
    private func updateGalleryBadge(count: Int) {
        let badgeTag = 999
        
        if count > 0 {
            if let existingBadge = galleryButton.viewWithTag(badgeTag) {
                if let label = existingBadge.subviews.first as? UILabel {
                    label.text = count > 99 ? "99+" : "\(count)"
                }
            } else {
                let badgeView = createBadgeView(count: count, tag: badgeTag)
                galleryButton.addSubview(badgeView)
                
                NSLayoutConstraint.activate([
                    badgeView.topAnchor.constraint(equalTo: galleryButton.topAnchor, constant: -4),
                    badgeView.trailingAnchor.constraint(equalTo: galleryButton.trailingAnchor, constant: 4),
                    badgeView.widthAnchor.constraint(greaterThanOrEqualToConstant: 20),
                    badgeView.heightAnchor.constraint(equalToConstant: 20)
                ])
            }
        } else {
            galleryButton.viewWithTag(badgeTag)?.removeFromSuperview()
        }
    }
    
    private func createBadgeView(count: Int, tag: Int) -> UIView {
        let badgeView = UIView()
        badgeView.tag = tag
        badgeView.backgroundColor = .systemYellow
        badgeView.translatesAutoresizingMaskIntoConstraints = false
        badgeView.layer.cornerRadius = 10
        
        let badgeLabel = UILabel()
        badgeLabel.text = count > 99 ? "99+" : "\(count)"
        badgeLabel.font = .systemFont(ofSize: 10, weight: .bold)
        badgeLabel.textColor = .black
        badgeLabel.translatesAutoresizingMaskIntoConstraints = false
        badgeLabel.setContentHuggingPriority(.required, for: .horizontal)
        
        badgeView.addSubview(badgeLabel)
        
        NSLayoutConstraint.activate([
            badgeLabel.centerXAnchor.constraint(equalTo: badgeView.centerXAnchor),
            badgeLabel.centerYAnchor.constraint(equalTo: badgeView.centerYAnchor)
        ])
        
        return badgeView
    }
    
    // MARK: - Feature Selection State
    
    private func updateFeatureSelectionState() {
        featureSelectionView.updateButtonStates(
            selectedFeatures: viewModel.selectedFeatures,
            allSelected: viewModel.areAllFeaturesSelected
        )
    }
    
    // MARK: - Alerts
    
    private func showPhotoSavedAlert(savedCount: Int, error: Error?) {
        let alert: UIAlertController
        
        if let error = error {
            alert = UIAlertController(title: "Save Failed", message: error.localizedDescription, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
        } else {
            let featureNames = Helper.sharedInstance.selectedFeatures.map { $0.rawValue }.joined(separator: ", ")
            let message = Helper.sharedInstance.selectedFeatures.isEmpty
                ? "\(savedCount) photo saved to gallery."
                : "\(savedCount) photos saved: Original + \(featureNames)"
            
            alert = UIAlertController(title: "✓ Saved!", message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "View Gallery", style: .default) { [weak self] _ in
                self?.galleryButtonTapped()
            })
            alert.addAction(UIAlertAction(title: "OK", style: .cancel))
        }
        
        present(alert, animated: true)
    }
    
    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .cancel))
        present(alert, animated: true)
    }
    
    private func showAlertWithSettings(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .cancel))
        alert.addAction(UIAlertAction(title: "Settings", style: .default) { _ in
            UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
        })
        present(alert, animated: true)
    }
}

// MARK: - FeatureSelectionViewDelegate

extension CameraViewController: FeatureSelectionViewDelegate {
    func featureSelectionView(_ view: FeatureSelectionView, didSelectFeature feature: FacialFeature) {
        viewModel.toggleFeature(feature)
        updateFeatureSelectionState()
    }
    
    func featureSelectionViewDidSelectAll(_ view: FeatureSelectionView) {
        viewModel.selectAllFeatures()
        updateFeatureSelectionState()
    }
}
