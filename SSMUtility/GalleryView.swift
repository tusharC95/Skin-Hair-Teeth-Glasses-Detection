//
//  GalleryView.swift
//  SSMUtility
//
//  SwiftUI Gallery view for browsing captured images
//

import SwiftUI
import Photos

// MARK: - Preference Key for Image Frames

struct ImageFramePreferenceKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]
    
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

// MARK: - Gallery View

struct GalleryView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var imageGroups: [ImageGroup] = []
    @State private var selectedImage: SavedImage?
    @State private var showingImageDetail = false
    @State private var isLoading = true
    
    // Multi-select state
    @State private var isSelectionMode = false
    @State private var selectedImages: Set<UUID> = []
    @State private var showingDeleteConfirmation = false
    
    // Drag selection state
    @State private var isDragging = false
    @State private var dragStartSelection: Set<UUID> = []
    @State private var dragSelectedImages: Set<UUID> = []
    @State private var imageFrames: [UUID: CGRect] = [:]
    
    private let columns = [
        GridItem(.flexible(), spacing: 4),
        GridItem(.flexible(), spacing: 4),
        GridItem(.flexible(), spacing: 4)
    ]
    
    private var totalImageCount: Int {
        imageGroups.flatMap { $0.images }.count
    }
    
    private var allImageIds: Set<UUID> {
        Set(imageGroups.flatMap { $0.images }.map { $0.id })
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background
                Color.black.ignoresSafeArea()
                
                if isLoading {
                    ProgressView()
                        .tint(.yellow)
                        .scaleEffect(1.5)
                } else if imageGroups.isEmpty {
                    emptyStateView
                } else {
                    galleryContent
                }
                
                // Bottom action bar when in selection mode
                if isSelectionMode && !selectedImages.isEmpty {
                    VStack {
                        Spacer()
                        selectionActionBar
                    }
                }
            }
            .navigationTitle(isSelectionMode ? "\(selectedImages.count) Selected" : "Gallery")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if isSelectionMode {
                        Button("Cancel") {
                            exitSelectionMode()
                        }
                        .foregroundColor(.yellow)
                    } else {
                        Button("Close") {
                            dismiss()
                        }
                        .foregroundColor(.yellow)
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 16) {
                        if !imageGroups.isEmpty {
                            if isSelectionMode {
                                // Select All / Deselect All button
                                Button(selectedImages.count == totalImageCount ? "Deselect All" : "Select All") {
                                    if selectedImages.count == totalImageCount {
                                        selectedImages.removeAll()
                                    } else {
                                        selectedImages = allImageIds
                                    }
                                }
                                .foregroundColor(.yellow)
                            } else {
                                // Select button
                                Button("Select") {
                                    withAnimation {
                                        isSelectionMode = true
                                    }
                                }
                                .foregroundColor(.yellow)
                            }
                        }
                    }
                }
            }
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            loadImages()
        }
        .onChange(of: showingImageDetail) { oldValue, newValue in
            // Refresh when returning from detail view
            if oldValue && !newValue {
                loadImages()
            }
        }
        .sheet(isPresented: $showingImageDetail) {
            if let image = selectedImage {
                ImageDetailView(savedImage: image) {
                    loadImages() // Refresh after deletion
                }
            }
        }
        .alert("Delete \(selectedImages.count) Photos?", isPresented: $showingDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                deleteSelectedImages()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone.")
        }
    }
    
    // MARK: - Views
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("No Photos Yet")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.white)
            
            Text("Captured photos will appear here")
                .font(.subheadline)
                .foregroundColor(.gray)
        }
    }
    
    private var galleryContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20, pinnedViews: [.sectionHeaders]) {
                ForEach(imageGroups) { group in
                    Section {
                        LazyVGrid(columns: columns, spacing: 4) {
                            ForEach(group.images) { image in
                                SelectableImageThumbnail(
                                    savedImage: image,
                                    isSelectionMode: isSelectionMode,
                                    isSelected: selectedImages.contains(image.id),
                                    isDragSelected: dragSelectedImages.contains(image.id),
                                    onTap: { handleImageTap(image) },
                                    onLongPress: { handleImageLongPress(image) }
                                )
                                .background(
                                    GeometryReader { geo in
                                        Color.clear
                                            .preference(
                                                key: ImageFramePreferenceKey.self,
                                                value: [image.id: geo.frame(in: .named("galleryScroll"))]
                                            )
                                    }
                                )
                            }
                        }
                    } header: {
                        dateSectionHeader(group.dateString, imageCount: group.images.count)
                    }
                }
            }
            .padding(.horizontal, 4)
            .padding(.bottom, isSelectionMode && !selectedImages.isEmpty ? 80 : 0)
        }
        .coordinateSpace(name: "galleryScroll")
        .onPreferenceChange(ImageFramePreferenceKey.self) { frames in
            imageFrames = frames
        }
        .simultaneousGesture(
            isSelectionMode ? dragSelectGesture : nil
        )
    }
    
    private var dragSelectGesture: some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .named("galleryScroll"))
            .onChanged { value in
                if !isDragging {
                    // Start dragging
                    isDragging = true
                    dragStartSelection = selectedImages
                    dragSelectedImages.removeAll()
                    
                    // Haptic feedback
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.impactOccurred()
                }
                
                // Find images that intersect with drag path
                let dragRect = CGRect(
                    x: min(value.startLocation.x, value.location.x),
                    y: min(value.startLocation.y, value.location.y),
                    width: abs(value.location.x - value.startLocation.x),
                    height: abs(value.location.y - value.startLocation.y)
                )
                
                var newDragSelected: Set<UUID> = []
                for (id, frame) in imageFrames {
                    if dragRect.intersects(frame) {
                        newDragSelected.insert(id)
                    }
                }
                
                // Light haptic when selection changes
                if newDragSelected != dragSelectedImages {
                    let generator = UISelectionFeedbackGenerator()
                    generator.selectionChanged()
                }
                
                dragSelectedImages = newDragSelected
                
                // Update selection: toggle images that are being dragged over
                var updatedSelection = dragStartSelection
                for id in dragSelectedImages {
                    if dragStartSelection.contains(id) {
                        updatedSelection.remove(id)
                    } else {
                        updatedSelection.insert(id)
                    }
                }
                selectedImages = updatedSelection
            }
            .onEnded { _ in
                isDragging = false
                dragSelectedImages.removeAll()
                dragStartSelection.removeAll()
            }
    }
    
    private func dateSectionHeader(_ dateString: String, imageCount: Int) -> some View {
        HStack {
            Text(dateString)
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.white)
            
            Text("(\(imageCount))")
                .font(.subheadline)
                .foregroundColor(.gray)
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.9))
    }
    
    private var selectionActionBar: some View {
        HStack(spacing: 20) {
            Spacer()
            
            Button(action: {
                showingDeleteConfirmation = true
            }) {
                HStack {
                    Image(systemName: "trash")
                    Text("Delete (\(selectedImages.count))")
                }
                .font(.headline)
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .background(Color.red)
                .cornerRadius(25)
            }
            
            Spacer()
        }
        .padding(.bottom, 20)
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0), Color.black.opacity(0.9)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 100)
            .allowsHitTesting(false)
        )
    }
    
    // MARK: - Methods
    
    private func loadImages() {
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let groups = ImageStorageManager.shared.loadImagesGroupedByDate()
            DispatchQueue.main.async {
                imageGroups = groups
                isLoading = false
                
                // Clean up selected images that no longer exist
                let existingIds = allImageIds
                selectedImages = selectedImages.intersection(existingIds)
            }
        }
    }
    
    private func handleImageTap(_ image: SavedImage) {
        if isSelectionMode {
            // Toggle selection
            withAnimation(.easeInOut(duration: 0.15)) {
                if selectedImages.contains(image.id) {
                    selectedImages.remove(image.id)
                } else {
                    selectedImages.insert(image.id)
                }
            }
        } else {
            // Show detail view
            selectedImage = image
            showingImageDetail = true
        }
    }
    
    private func handleImageLongPress(_ image: SavedImage) {
        if !isSelectionMode {
            // Enter selection mode and select this image
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            
            withAnimation {
                isSelectionMode = true
                selectedImages.insert(image.id)
            }
        }
    }
    
    private func exitSelectionMode() {
        withAnimation {
            isSelectionMode = false
            selectedImages.removeAll()
            dragSelectedImages.removeAll()
        }
    }
    
    private func deleteSelectedImages() {
        let allImages = imageGroups.flatMap { $0.images }
        let imagesToDelete = allImages.filter { selectedImages.contains($0.id) }
        
        let _ = ImageStorageManager.shared.deleteImages(imagesToDelete)
        
        exitSelectionMode()
        loadImages()
    }
}

// MARK: - Selectable Image Thumbnail

struct SelectableImageThumbnail: View {
    let savedImage: SavedImage
    var isSelectionMode: Bool = false
    var isSelected: Bool = false
    var isDragSelected: Bool = false
    var onTap: () -> Void
    var onLongPress: () -> Void
    
    @State private var thumbnail: UIImage?
    @State private var aspectRatio: CGFloat = 3/4  // Default portrait ratio
    
    private var showSelected: Bool {
        isSelected || isDragSelected
    }
    
    var body: some View {
        ZStack {
            if let thumbnail = thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .clipped()
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                ProgressView()
                    .tint(.white)
            }
            
            // Selection overlay
            if isSelectionMode {
                // Dimming overlay when not selected
                if !showSelected {
                    Color.black.opacity(0.3)
                }
                
                // Drag highlight effect
                if isDragSelected && !isSelected {
                    Color.yellow.opacity(0.2)
                }
                
                // Selection indicator
                VStack {
                    HStack {
                        Spacer()
                        ZStack {
                            Circle()
                                .fill(showSelected ? Color.yellow : Color.white.opacity(0.3))
                                .frame(width: 24, height: 24)
                            
                            if showSelected {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.black)
                            } else {
                                Circle()
                                    .stroke(Color.white, lineWidth: 2)
                                    .frame(width: 24, height: 24)
                            }
                        }
                        .padding(6)
                    }
                    Spacer()
                }
            }
            
            // Feature type badge
            if let featureType = savedImage.featureType {
                VStack {
                    Spacer()
                    HStack {
                        Text(featureType)
                            .font(.caption2)
                            .fontWeight(.medium)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(featureColor(featureType))
                            .foregroundColor(.black)
                            .cornerRadius(4)
                        Spacer()
                    }
                    .padding(4)
                }
            }
            
            // Selected border
            if showSelected {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.yellow, lineWidth: 3)
            }
        }
        .aspectRatio(aspectRatio, contentMode: .fit)
        .cornerRadius(8)
        .scaleEffect(showSelected ? 0.95 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: showSelected)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
        .onLongPressGesture {
            onLongPress()
        }
        .onAppear {
            loadThumbnail()
        }
    }
    
    private func loadThumbnail() {
        DispatchQueue.global(qos: .userInitiated).async {
            if let image = ImageStorageManager.shared.loadImage(for: savedImage) {
                // Calculate aspect ratio from original image
                let ratio = image.size.width / image.size.height
                
                // Create a smaller thumbnail for performance (maintain aspect ratio)
                let maxDimension: CGFloat = 300
                let scale = min(maxDimension / image.size.width, maxDimension / image.size.height)
                let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                
                UIGraphicsBeginImageContextWithOptions(newSize, false, 0)
                image.draw(in: CGRect(origin: .zero, size: newSize))
                let resized = UIGraphicsGetImageFromCurrentImageContext()
                UIGraphicsEndImageContext()
                
                DispatchQueue.main.async {
                    aspectRatio = ratio
                    thumbnail = resized
                }
            }
        }
    }
    
    private func featureColor(_ type: String) -> Color {
        switch type.lowercased() {
        case "skin": return .yellow
        case "hair": return .orange
        case "teeth": return Color(white: 0.85)  // Light gray for visibility
        case "glasses": return .cyan
        default: return .gray
        }
    }
}

// MARK: - Preview

struct GalleryView_Previews: PreviewProvider {
    static var previews: some View {
        GalleryView()
    }
}
