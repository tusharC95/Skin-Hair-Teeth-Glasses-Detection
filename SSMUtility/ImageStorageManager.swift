//
//  ImageStorageManager.swift
//  SSMUtility
//
//  Sandboxed storage manager for captured images
//

import Foundation
import UIKit

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
                print("Created images directory at: \(imagesDirectory.path)")
            } catch {
                print("Error creating images directory: \(error)")
            }
        }
    }
    
    // MARK: - Save Images
    
    /// Save an image to sandboxed storage
    /// - Parameters:
    ///   - image: The UIImage to save
    ///   - featureType: Optional feature type (Skin, Hair, Teeth, Glasses)
    ///   - captureDate: The date/time of capture
    /// - Returns: The saved image metadata, or nil if failed
    @discardableResult
    func saveImage(_ image: UIImage, featureType: String? = nil, captureDate: Date = Date()) -> SavedImage? {
        let id = UUID()
        let filename = "\(id.uuidString).jpg"
        let fileURL = imagesDirectory.appendingPathComponent(filename)
        
        // Convert to JPEG data
        guard let imageData = image.jpegData(compressionQuality: 0.9) else {
            print("Error: Could not convert image to JPEG")
            return nil
        }
        
        // Write to file
        do {
            try imageData.write(to: fileURL)
        } catch {
            print("Error saving image: \(error)")
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
        
        print("Saved image: \(filename) with feature: \(featureType ?? "Original")")
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
            print("No metadata file found or unable to read")
            return []
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        do {
            let images = try decoder.decode([SavedImage].self, from: data)
            print("Loaded \(images.count) images from metadata")
            return images
        } catch {
            print("Error decoding image metadata: \(error)")
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
        let fileURL = imagesDirectory.appendingPathComponent(savedImage.filename)
        
        do {
            try fileManager.removeItem(at: fileURL)
            
            // Update metadata
            var allImages = loadAllImageMetadata()
            allImages.removeAll { $0.id == savedImage.id }
            saveAllImageMetadata(allImages)
            
            return true
        } catch {
            print("Error deleting image: \(error)")
            return false
        }
    }
    
    /// Delete all images
    func deleteAllImages() {
        do {
            try fileManager.removeItem(at: imagesDirectory)
            createImagesDirectoryIfNeeded()
            print("Deleted all images")
        } catch {
            print("Error deleting all images: \(error)")
        }
    }
    
    // MARK: - Metadata Persistence
    
    private func saveAllImageMetadata(_ images: [SavedImage]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        guard let data = try? encoder.encode(images) else {
            print("Error encoding image metadata")
            return
        }
        
        do {
            try data.write(to: metadataURL)
        } catch {
            print("Error saving metadata: \(error)")
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
    
    // MARK: - Storage Info
    
    /// Get total storage used by saved images
    func getStorageUsed() -> String {
        var totalSize: Int64 = 0
        
        if let enumerator = fileManager.enumerator(at: imagesDirectory, includingPropertiesForKeys: [.fileSizeKey]) {
            while let fileURL = enumerator.nextObject() as? URL {
                if let fileSize = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    totalSize += Int64(fileSize)
                }
            }
        }
        
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: totalSize)
    }
    
    /// Get total number of saved images
    func getImageCount() -> Int {
        return loadAllImageMetadata().count
    }
}
