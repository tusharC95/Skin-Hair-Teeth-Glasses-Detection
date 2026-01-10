/*
 GalleryViewModel.swift
 SSMUtility

 ViewModel for GalleryView - manages gallery state, selection, and deletion logic.
*/

import Foundation
import UIKit

// MARK: - GalleryViewModel

class GalleryViewModel: ObservableObject {
    
    // MARK: - Error State
    
    @Published var errorMessage: String?
    @Published var showingError = false
    
    // MARK: - Published State
    
    @Published private(set) var imageGroups: [ImageGroup] = []
    @Published private(set) var isLoading = true
    
    // Selection state
    @Published var isSelectionMode = false
    @Published var selectedImages: Set<UUID> = []
    
    // Drag selection state
    @Published var isDragging = false
    @Published var dragSelectedImages: Set<UUID> = []
    private var dragStartSelection: Set<UUID> = []
    
    // Image frames for drag selection
    var imageFrames: [UUID: CGRect] = [:]
    
    // MARK: - Computed Properties
    
    var totalImageCount: Int {
        imageGroups.flatMap { $0.images }.count
    }
    
    var allImageIds: Set<UUID> {
        Set(imageGroups.flatMap { $0.images }.map { $0.id })
    }
    
    var hasImages: Bool {
        !imageGroups.isEmpty
    }
    
    var selectedCount: Int {
        selectedImages.count
    }
    
    var areAllSelected: Bool {
        selectedImages.count == totalImageCount && totalImageCount > 0
    }
    
    var hasSelection: Bool {
        !selectedImages.isEmpty
    }
    
    // MARK: - Initialization
    
    init() {}
    
    // MARK: - Image Loading
    
    func loadImages() {
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let groups = ImageStorageManager.shared.loadImagesGroupedByDate()
            DispatchQueue.main.async {
                self?.imageGroups = groups
                self?.isLoading = false
                self?.cleanupInvalidSelections()
            }
        }
    }
    
    private func cleanupInvalidSelections() {
        let existingIds = allImageIds
        selectedImages = selectedImages.intersection(existingIds)
    }
    
    // MARK: - Selection Mode
    
    func enterSelectionMode(selectingImage image: SavedImage? = nil) {
        isSelectionMode = true
        if let image = image {
            selectedImages.insert(image.id)
        }
    }
    
    func exitSelectionMode() {
        isSelectionMode = false
        selectedImages.removeAll()
        dragSelectedImages.removeAll()
        isDragging = false
    }
    
    // MARK: - Image Selection
    
    func toggleSelection(for image: SavedImage) {
        if selectedImages.contains(image.id) {
            selectedImages.remove(image.id)
        } else {
            selectedImages.insert(image.id)
        }
    }
    
    func selectAll() {
        selectedImages = allImageIds
    }
    
    func deselectAll() {
        selectedImages.removeAll()
    }
    
    func toggleSelectAll() {
        if areAllSelected {
            deselectAll()
        } else {
            selectAll()
        }
    }
    
    func isSelected(_ image: SavedImage) -> Bool {
        selectedImages.contains(image.id)
    }
    
    func isDragSelected(_ image: SavedImage) -> Bool {
        dragSelectedImages.contains(image.id)
    }
    
    // MARK: - Drag Selection
    
    func startDragSelection() {
        isDragging = true
        dragStartSelection = selectedImages
        dragSelectedImages.removeAll()
    }
    
    func updateDragSelection(startLocation: CGPoint, currentLocation: CGPoint) -> Bool {
        // Calculate drag rectangle
        let dragRect = CGRect(
            x: min(startLocation.x, currentLocation.x),
            y: min(startLocation.y, currentLocation.y),
            width: abs(currentLocation.x - startLocation.x),
            height: abs(currentLocation.y - startLocation.y)
        )
        
        // Find images that intersect with drag rectangle
        var newDragSelected: Set<UUID> = []
        for (id, frame) in imageFrames {
            if dragRect.intersects(frame) {
                newDragSelected.insert(id)
            }
        }
        
        let selectionChanged = newDragSelected != dragSelectedImages
        dragSelectedImages = newDragSelected
        
        // Update selection: toggle images being dragged over
        var updatedSelection = dragStartSelection
        for id in dragSelectedImages {
            if dragStartSelection.contains(id) {
                updatedSelection.remove(id)
            } else {
                updatedSelection.insert(id)
            }
        }
        selectedImages = updatedSelection
        
        return selectionChanged
    }
    
    func endDragSelection() {
        isDragging = false
        dragSelectedImages.removeAll()
        dragStartSelection.removeAll()
    }
    
    func updateImageFrame(id: UUID, frame: CGRect) {
        imageFrames[id] = frame
    }
    
    // MARK: - Deletion
    
    func deleteSelectedImages() -> Int {
        let allImages = imageGroups.flatMap { $0.images }
        let imagesToDelete = allImages.filter { selectedImages.contains($0.id) }
        
        let result = ImageStorageManager.shared.deleteImages(imagesToDelete)
        
        if result.failed > 0 {
            if let error = ImageStorageManager.shared.lastError {
                errorMessage = error.errorDescription
            } else {
                errorMessage = "Failed to delete \(result.failed) photo(s)"
            }
            showingError = true
        }
        
        exitSelectionMode()
        loadImages()
        
        return result.deleted
    }
}
