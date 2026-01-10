//
//  ImageStorageManager.swift
//  SSMUtility
//
//  Sandboxed storage manager for captured images
//

import Foundation
import UIKit

// MARK: - Storage Errors

enum ImageStorageError: LocalizedError {
    case directoryCreationFailed
    case imageConversionFailed
    case saveFailed(underlying: Error)
    case deleteFailed(underlying: Error)
    case metadataDecodingFailed
    case imageNotFound
    
    var errorDescription: String? {
        switch self {
        case .directoryCreationFailed:
            return "Could not create storage directory"
        case .imageConversionFailed:
            return "Could not process image for saving"
        case .saveFailed(let error):
            return "Failed to save image: \(error.localizedDescription)"
        case .deleteFailed(let error):
            return "Failed to delete image: \(error.localizedDescription)"
        case .metadataDecodingFailed:
            return "Could not read saved images"
        case .imageNotFound:
            return "Image file not found"
        }
    }
}

/// Represents a saved image with metadata
struct SavedImage: Identifiable, Codable {
    let id: UUID
    let filename: String
    let captureDate: Date
    let featureType: String? // "Skin", "Hair", "Teeth", "Glasses", or nil for original
    
    var dateString: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: captureDate)
    }
    
    var timeString: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: captureDate)
    }
}

/// Groups images by capture date
struct ImageGroup: Identifiable {
    let id: String // Date string as ID
    let date: Date
    let dateString: String
    var images: [SavedImage]
}

/// Manager for sandboxed image storage
class ImageStorageManager {
    
    static let shared = ImageStorageManager()
    
    private let fileManager = FileManager.default
    private let imagesDirectoryName = "CapturedPhotos"
    private let metadataFileName = "images_metadata.json"
    
    private var imagesDirectory: URL {
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsPath.appendingPathComponent(imagesDirectoryName)
    }
    
    private var metadataURL: URL {
        return imagesDirectory.appendingPathComponent(metadataFileName)
    }
    
    private init() {
        createImagesDirectoryIfNeeded()
    }
    
    // MARK: - Directory Management
    
    private func createImagesDirectoryIfNeeded() {
        if !fileManager.fileExists(atPath: imagesDirectory.path) {
            do {
                try fileManager.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
            } catch {
                lastError = .directoryCreationFailed
            }
        }
    }
    
    /// Last error that occurred during an operation
    private(set) var lastError: ImageStorageError?
    
    // MARK: - Save Images
    
    /// Save an image to sandboxed storage
    /// - Parameters:
    ///   - image: The UIImage to save
    ///   - featureType: Optional feature type (Skin, Hair, Teeth, Glasses)
    ///   - captureDate: The date/time of capture
    /// - Returns: The saved image metadata, or nil if failed
    @discardableResult
    func saveImage(_ image: UIImage, featureType: String? = nil, captureDate: Date = Date()) -> SavedImage? {
        lastError = nil
        
        let id = UUID()
        let filename = "\(id.uuidString).jpg"
        let fileURL = imagesDirectory.appendingPathComponent(filename)
        
        // Convert to JPEG data
        guard let imageData = image.jpegData(compressionQuality: 0.9) else {
            lastError = .imageConversionFailed
            return nil
        }
        
        // Write to file
        do {
            try imageData.write(to: fileURL)
        } catch {
            lastError = .saveFailed(underlying: error)
            return nil
        }
        
        // Create metadata
        let savedImage = SavedImage(
            id: id,
            filename: filename,
            captureDate: captureDate,
            featureType: featureType
        )
        
        // Update metadata file
        var allImages = loadAllImageMetadata()
        allImages.append(savedImage)
        saveAllImageMetadata(allImages)
        
        return savedImage
    }
    
    // MARK: - Load Images
    
    /// Load an image by its metadata
    func loadImage(for savedImage: SavedImage) -> UIImage? {
        let fileURL = imagesDirectory.appendingPathComponent(savedImage.filename)
        guard let imageData = try? Data(contentsOf: fileURL) else {
            return nil
        }
        return UIImage(data: imageData)
    }
    
    /// Load all saved images metadata
    func loadAllImageMetadata() -> [SavedImage] {
        guard let data = try? Data(contentsOf: metadataURL) else {
            // No metadata file yet - this is normal for first launch
            return []
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        do {
            let images = try decoder.decode([SavedImage].self, from: data)
            return images
        } catch {
            lastError = .metadataDecodingFailed
            return []
        }
    }
    
    /// Load images grouped by date
    func loadImagesGroupedByDate() -> [ImageGroup] {
        let allImages = loadAllImageMetadata()
        
        // Group by date (ignoring time)
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: allImages) { image -> String in
            let components = calendar.dateComponents([.year, .month, .day], from: image.captureDate)
            return "\(components.year!)-\(components.month!)-\(components.day!)"
        }
        
        // Convert to ImageGroup array
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        
        var groups: [ImageGroup] = []
        for (dateKey, images) in grouped {
            if let firstImage = images.first {
                let dateString = formatter.string(from: firstImage.captureDate)
                let group = ImageGroup(
                    id: dateKey,
                    date: firstImage.captureDate,
                    dateString: dateString,
                    images: images.sorted { $0.captureDate > $1.captureDate }
                )
                groups.append(group)
            }
        }
        
        // Sort groups by date (newest first)
        return groups.sorted { $0.date > $1.date }
    }
    
    // MARK: - Delete Images
    
    /// Delete a single image
    func deleteImage(_ savedImage: SavedImage) -> Bool {
        lastError = nil
        let fileURL = imagesDirectory.appendingPathComponent(savedImage.filename)
        
        do {
            try fileManager.removeItem(at: fileURL)
            
            // Update metadata
            var allImages = loadAllImageMetadata()
            allImages.removeAll { $0.id == savedImage.id }
            saveAllImageMetadata(allImages)
            
            return true
        } catch {
            lastError = .deleteFailed(underlying: error)
            return false
        }
    }
    
    /// Delete multiple images at once
    /// - Returns: Tuple with (deletedCount, failedCount)
    func deleteImages(_ imagesToDelete: [SavedImage]) -> (deleted: Int, failed: Int) {
        lastError = nil
        var deletedCount = 0
        var failedCount = 0
        var allImages = loadAllImageMetadata()
        let idsToDelete = Set(imagesToDelete.map { $0.id })
        
        for image in imagesToDelete {
            let fileURL = imagesDirectory.appendingPathComponent(image.filename)
            do {
                try fileManager.removeItem(at: fileURL)
                deletedCount += 1
            } catch {
                failedCount += 1
                lastError = .deleteFailed(underlying: error)
            }
        }
        
        // Update metadata once for all deletions
        allImages.removeAll { idsToDelete.contains($0.id) }
        saveAllImageMetadata(allImages)
        
        return (deleted: deletedCount, failed: failedCount)
    }
    
    // MARK: - Metadata Persistence
    
    private func saveAllImageMetadata(_ images: [SavedImage]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        guard let data = try? encoder.encode(images) else {
            lastError = .metadataDecodingFailed
            return
        }
        
        do {
            try data.write(to: metadataURL)
        } catch {
            lastError = .saveFailed(underlying: error)
        }
    }
    
    // MARK: - Export to Photos
    
    /// Export an image to the system Photo Library
    func exportToPhotoLibrary(_ savedImage: SavedImage, completion: @escaping (Bool, Error?) -> Void) {
        guard let image = loadImage(for: savedImage) else {
            completion(false, NSError(domain: "ImageStorageManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Could not load image"]))
            return
        }
        
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        completion(true, nil)
    }
    
    /// Get total number of saved images
    func getImageCount() -> Int {
        return loadAllImageMetadata().count
    }
}
