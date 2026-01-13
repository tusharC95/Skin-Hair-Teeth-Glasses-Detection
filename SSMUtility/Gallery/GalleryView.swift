/*
 GalleryView.swift
 SSMUtility

 SwiftUI Gallery view for browsing captured images.
 UI layer - delegates business logic to GalleryViewModel.
*/

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
    @StateObject private var viewModel = GalleryViewModel()
    
    // Detail view state
    @State private var selectedImageIndex: Int = 0
    @State private var showingImageDetail = false
    @State private var showingDeleteConfirmation = false
    
    private let columns = [
        GridItem(.flexible(), spacing: 4),
        GridItem(.flexible(), spacing: 4),
        GridItem(.flexible(), spacing: 4)
    ]

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                if viewModel.isLoading {
                    loadingView
                } else if !viewModel.hasImages {
                    emptyStateView
                } else {
                    galleryContent
                }
                
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                if viewModel.isSelectionMode && viewModel.hasSelection {
                    selectionActionBar
                }

                AdMobBannerView(adUnitID: AdMobManager.shared.bannerAdUnitID)
                    .frame(height: 50)
                    .padding(.vertical, 8)
            }
            .background(Color.black)
        }
        .onAppear {
            viewModel.loadImages()
        }
        .onChange(of: showingImageDetail) { oldValue, newValue in
            if oldValue && !newValue {
                viewModel.loadImages()
            }
        }
        .fullScreenCover(isPresented: $showingImageDetail) {
            ImagePagerView(
                allImages: viewModel.allImages,
                currentIndex: selectedImageIndex,
                onDelete: {
                    viewModel.loadImages()
                }
            )
        }
        .alert("Delete \(viewModel.selectedCount) Photos?", isPresented: $showingDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                let _ = viewModel.deleteSelectedImages()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone.")
        }
        .alert("Error", isPresented: $viewModel.showingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "An error occurred")
        }
    }
    
    // MARK: - Computed Properties
    
    private var navigationTitle: String {
        viewModel.isSelectionMode ? "\(viewModel.selectedCount) Selected" : "Gallery"
    }
    
    // MARK: - Toolbar
    
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            leadingToolbarButton
        }
        
        ToolbarItem(placement: .navigationBarTrailing) {
            trailingToolbarButton
        }
    }
    
    @ViewBuilder
    private var leadingToolbarButton: some View {
        if viewModel.isSelectionMode {
            Button("Cancel") {
                withAnimation {
                    viewModel.exitSelectionMode()
                }
            }
            .foregroundColor(.yellow)
        } else {
            Button("Close") {
                dismiss()
            }
            .foregroundColor(.yellow)
        }
    }
    
    @ViewBuilder
    private var trailingToolbarButton: some View {
        if viewModel.hasImages {
            if viewModel.isSelectionMode {
                Button(viewModel.areAllSelected ? "Deselect All" : "Select All") {
                    viewModel.toggleSelectAll()
                }
                .foregroundColor(.yellow)
            } else {
                Button("Select") {
                    withAnimation {
                        viewModel.enterSelectionMode()
                    }
                }
                .foregroundColor(.yellow)
            }
        }
    }
    
    // MARK: - Views
    
    private var loadingView: some View {
        ProgressView()
            .tint(.yellow)
            .scaleEffect(1.5)
    }
    
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
                ForEach(viewModel.imageGroups) { group in
                    Section {
                        imageGrid(for: group)
                    } header: {
                        dateSectionHeader(group.dateString, imageCount: group.images.count)
                    }
                }
            }
            .padding(.horizontal, 4)
        }
        .coordinateSpace(name: "galleryScroll")
        .onPreferenceChange(ImageFramePreferenceKey.self) { frames in
            for (id, frame) in frames {
                viewModel.updateImageFrame(id: id, frame: frame)
            }
        }
        .simultaneousGesture(
            viewModel.isSelectionMode ? dragSelectGesture : nil
        )
    }
    
    private func imageGrid(for group: ImageGroup) -> some View {
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(group.images) { image in
                SelectableImageThumbnail(
                    savedImage: image,
                    isSelectionMode: viewModel.isSelectionMode,
                    isSelected: viewModel.isSelected(image),
                    isDragSelected: viewModel.isDragSelected(image),
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
    }
    
    private var dragSelectGesture: some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .named("galleryScroll"))
            .onChanged { value in
                if !viewModel.isDragging {
                    viewModel.startDragSelection()
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
                
                let selectionChanged = viewModel.updateDragSelection(
                    startLocation: value.startLocation,
                    currentLocation: value.location
                )
                
                if selectionChanged {
                    UISelectionFeedbackGenerator().selectionChanged()
                }
            }
            .onEnded { _ in
                viewModel.endDragSelection()
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
                    Text("Delete (\(viewModel.selectedCount))")
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
    
    // MARK: - Actions
    
    private func handleImageTap(_ image: SavedImage) {
        if viewModel.isSelectionMode {
            withAnimation(.easeInOut(duration: 0.15)) {
                viewModel.toggleSelection(for: image)
            }
        } else {
            // Find the index of the tapped image in allImages
            if let index = viewModel.allImages.firstIndex(where: { $0.id == image.id }) {
                selectedImageIndex = index
                showingImageDetail = true
            }
        }
    }
    
    private func handleImageLongPress(_ image: SavedImage) {
        if !viewModel.isSelectionMode {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            withAnimation {
                viewModel.enterSelectionMode(selectingImage: image)
            }
        }
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
    @State private var aspectRatio: CGFloat = 3/4
    
    private var showSelected: Bool {
        isSelected || isDragSelected
    }
    
    var body: some View {
        ZStack {
            thumbnailImage
            
            if isSelectionMode {
                selectionOverlay
            }
            
            featureBadge
            
            if showSelected {
                selectedBorder
            }
        }
        .aspectRatio(aspectRatio, contentMode: .fit)
        .cornerRadius(8)
        .scaleEffect(showSelected ? 0.95 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: showSelected)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .onLongPressGesture { onLongPress() }
        .onAppear { loadThumbnail() }
    }
    
    // MARK: - Subviews
    
    @ViewBuilder
    private var thumbnailImage: some View {
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
    }
    
    private var selectionOverlay: some View {
        ZStack {
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
                    selectionIndicator
                        .padding(6)
                }
                Spacer()
            }
        }
    }
    
    private var selectionIndicator: some View {
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
    }
    
    @ViewBuilder
    private var featureBadge: some View {
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
    }
    
    private var selectedBorder: some View {
        RoundedRectangle(cornerRadius: 8)
            .stroke(Color.yellow, lineWidth: 3)
    }
    
    // MARK: - Methods
    
    private func loadThumbnail() {
        DispatchQueue.global(qos: .userInitiated).async {
            if let image = ImageStorageManager.shared.loadImage(for: savedImage) {
                let ratio = image.size.width / image.size.height
                
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
        case "teeth": return Color(white: 0.85)
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
