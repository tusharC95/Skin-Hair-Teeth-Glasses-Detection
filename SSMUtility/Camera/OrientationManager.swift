/*
 OrientationManager.swift
 SSMUtility

 Handles device orientation detection using CoreMotion for reliable
 orientation tracking even when interface orientation is locked.
*/

import UIKit
import CoreMotion

// MARK: - Protocol

protocol OrientationManagerDelegate: AnyObject {
    func orientationManager(_ manager: OrientationManager, didChangeToLandscape isLandscape: Bool)
}

// MARK: - OrientationManager

class OrientationManager {
    
    // MARK: - Properties
    
    weak var delegate: OrientationManagerDelegate?
    
    private let motionManager = CMMotionManager()
    private(set) var isCurrentlyLandscape = false
    private var isMonitoring = false
    
    // Threshold for landscape detection (0.5 = 30 degrees from horizontal)
    var landscapeThreshold: Double = 0.5
    
    // Update interval for motion updates (seconds)
    var updateInterval: TimeInterval = 0.2
    
    // MARK: - Initialization
    
    init() {}
    
    deinit {
        stopMonitoring()
    }
    
    // MARK: - Public Methods
    
    func startMonitoring() {
        guard !isMonitoring else { return }
        
        // Reset state
        isCurrentlyLandscape = false
        isMonitoring = true
        
        if motionManager.isDeviceMotionAvailable {
            startCoreMotionMonitoring()
        } else {
            startFallbackMonitoring()
        }
    }
    
    func stopMonitoring() {
        guard isMonitoring else { return }
        
        isMonitoring = false
        
        if motionManager.isDeviceMotionActive {
            motionManager.stopDeviceMotionUpdates()
        }
        
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
        NotificationCenter.default.removeObserver(self, name: UIDevice.orientationDidChangeNotification, object: nil)
    }
    
    // MARK: - Private Methods
    
    private func startCoreMotionMonitoring() {
        motionManager.deviceMotionUpdateInterval = updateInterval
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
            guard let self = self, let motion = motion, error == nil else { return }
            self.handleMotionUpdate(motion)
        }
    }
    
    private func startFallbackMonitoring() {
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(deviceOrientationDidChange),
            name: UIDevice.orientationDidChangeNotification,
            object: nil
        )
        // Check current orientation immediately
        checkDeviceOrientation()
    }
    
    private func handleMotionUpdate(_ motion: CMDeviceMotion) {
        let gravity = motion.gravity
        
        // Determine orientation based on gravity
        // When device is upright (portrait): gravity.y is close to -1
        // When device is landscape: gravity.x is close to +/-1
        let isLandscape = abs(gravity.x) > abs(gravity.y) && abs(gravity.x) > landscapeThreshold
        
        // Only notify if state changed
        if isLandscape != isCurrentlyLandscape {
            isCurrentlyLandscape = isLandscape
            delegate?.orientationManager(self, didChangeToLandscape: isLandscape)
        }
    }
    
    @objc private func deviceOrientationDidChange() {
        checkDeviceOrientation()
    }
    
    private func checkDeviceOrientation() {
        let orientation = UIDevice.current.orientation
        
        let isLandscape = orientation.isLandscape
        let isPortrait = orientation.isPortrait
        
        if isLandscape && !isCurrentlyLandscape {
            isCurrentlyLandscape = true
            delegate?.orientationManager(self, didChangeToLandscape: true)
        } else if isPortrait && isCurrentlyLandscape {
            isCurrentlyLandscape = false
            delegate?.orientationManager(self, didChangeToLandscape: false)
        }
        // Ignore .faceUp, .faceDown, .unknown - keep current state
    }
}
