//
//  GalleryView.swift
//  SSMUtility
//
//  SwiftUI Gallery view for browsing captured images
//

import SwiftUI
import Photos

struct GalleryView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var imageGroups: [ImageGroup] = []
    @State private var selectedImage: SavedImage?
    @State private var showingImageDetail = false
    @State private var isLoading = true
    
    private let columns = [
        GridItem(.flexible(), spacing: 4),
        GridItem(.flexible(), spacing: 4),
        GridItem(.flexible(), spacing: 4)
    ]
    
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
            }
            .navigationTitle("Gallery")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                    .foregroundColor(.yellow)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Text("\(ImageStorageManager.shared.getImageCount()) photos")
                        .font(.subheadline)
                        .foregroundColor(.yellow)
                        .padding(.horizontal, 8)
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
                                ImageThumbnail(savedImage: image)
                                    .onTapGesture {
                                        selectedImage = image
                                        showingImageDetail = true
                                    }
                            }
                        }
                    } header: {
                        dateSectionHeader(group.dateString)
                    }
                }
            }
            .padding(.horizontal, 4)
        }
    }
    
    private func dateSectionHeader(_ dateString: String) -> some View {
        HStack {
            Text(dateString)
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.white)
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.9))
    }
    
    // MARK: - Methods
    
    private func loadImages() {
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let groups = ImageStorageManager.shared.loadImagesGroupedByDate()
            DispatchQueue.main.async {
                imageGroups = groups
                isLoading = false
            }
        }
    }
}

// MARK: - Image Thumbnail

struct ImageThumbnail: View {
    let savedImage: SavedImage
    @State private var thumbnail: UIImage?
    @State private var aspectRatio: CGFloat = 3/4  // Default portrait ratio
    
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
        }
        .aspectRatio(aspectRatio, contentMode: .fit)
        .cornerRadius(8)
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
