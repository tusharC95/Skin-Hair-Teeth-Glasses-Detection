/*
 ImageDetailViewModel.swift
 SSMUtility

 ViewModel for ImageDetailView - manages image display, export, and deletion.
*/

import Foundation
import UIKit
import Photos
import Sentry

private let logger = SentrySDK.logger

// MARK: - ImageDetailViewModel

class ImageDetailViewModel: ObservableObject {
    
    // MARK: - Published State
    
    @Published private(set) var image: UIImage?
    @Published private(set) var isLoading = true
    @Published var showingDeleteConfirmation = false
    @Published var showingExportAlert = false
    @Published var showingShareSheet = false
    @Published var showingError = false
    @Published private(set) var exportSuccess = false
    @Published private(set) var exportMessage = ""
    @Published private(set) var errorMessage = ""
    
    // MARK: - Properties
    
    let savedImage: SavedImage
    private var onDelete: (() -> Void)?
    
    // MARK: - Computed Properties
    
    var navigationTitle: String {
        savedImage.featureType ?? "Original Photo"
    }
    
    var featureType: String? {
        savedImage.featureType
    }
    
    var dateString: String {
        savedImage.dateString
    }
    
    var timeString: String {
        savedImage.timeString
    }
    
    // MARK: - Initialization
    
    init(savedImage: SavedImage, onDelete: @escaping () -> Void) {
        self.savedImage = savedImage
        self.onDelete = onDelete
    }
    
    // MARK: - Image Loading
    
    func loadImage() {
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let loadedImage = ImageStorageManager.shared.loadImage(for: self.savedImage)
            DispatchQueue.main.async {
                self.image = loadedImage
                self.isLoading = false
            }
        }
    }
    
    // MARK: - Actions
    
    func deleteImage() -> Bool {
        logger.info("Deleting image", attributes: [
            "filename": savedImage.filename,
            "featureType": savedImage.featureType ?? "Original"
        ])
        
        let success = ImageStorageManager.shared.deleteImage(savedImage)
        if success {
            logger.debug("Image deleted successfully")
            onDelete?()
        } else {
            if let error = ImageStorageManager.shared.lastError {
                errorMessage = error.errorDescription ?? "Failed to delete image"
            } else {
                errorMessage = "Failed to delete image"
            }
            logger.error("Failed to delete image")
            showingError = true
        }
        return success
    }
    
    func exportToPhotos() {
        logger.info("Exporting image to Photos")
        
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { [weak self] status in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                if status == .authorized || status == .limited {
                    ImageStorageManager.shared.exportToPhotoLibrary(self.savedImage) { success, error in
                        DispatchQueue.main.async {
                            self.exportSuccess = success
                            self.exportMessage = success 
                                ? "Photo saved to your Photo Library."
                                : "Could not save photo. Please check permissions."
                            self.showingExportAlert = true
                            
                            if success {
                                logger.info("Image exported to Photos successfully")
                            } else {
                                logger.warn("Failed to export image to Photos")
                            }
                        }
                    }
                } else {
                    self.exportSuccess = false
                    self.exportMessage = "Could not save photo. Please check permissions."
                    self.showingExportAlert = true
                    logger.warn("Photo library access denied")
                }
            }
        }
    }
    
    func shareImage() {
        logger.info("Sharing image")
        showingShareSheet = true
    }
    
    func confirmDelete() {
        showingDeleteConfirmation = true
    }
    
    // MARK: - Feature Helpers
    
    func featureIcon(for type: String) -> String {
        switch type.lowercased() {
        case "skin": return "face.smiling"
        case "hair": return "person.crop.circle"
        case "teeth": return "mouth"
        case "glasses": return "eyeglasses"
        default: return "photo"
        }
    }
    
    func featureColorName(for type: String) -> FeatureColorType {
        switch type.lowercased() {
        case "skin": return .skin
        case "hair": return .hair
        case "teeth": return .teeth
        case "glasses": return .glasses
        default: return .other
        }
    }
}

// MARK: - Feature Color Type

enum FeatureColorType {
    case skin, hair, teeth, glasses, other
}
