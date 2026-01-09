//
//  ImageDetailView.swift
//  SSMUtility
//
//  SwiftUI view for viewing a single image with export/delete options
//

import SwiftUI
import Photos

struct ImageDetailView: View {
    let savedImage: SavedImage
    let onDelete: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var showingDeleteConfirmation = false
    @State private var showingExportAlert = false
    @State private var exportSuccess = false
    @State private var showingShareSheet = false
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                if let image = image {
                    imageView(image)
                } else {
                    ProgressView()
                        .tint(.yellow)
                        .scaleEffect(1.5)
                }
            }
            .navigationTitle(savedImage.featureType ?? "Original Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                    .foregroundColor(.yellow)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            shareImage()
                        } label: {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                        
                        Button {
                            exportToPhotos()
                        } label: {
                            Label("Save to Photos", systemImage: "photo.on.rectangle")
                        }
                        
                        Divider()
                        
                        Button(role: .destructive) {
                            showingDeleteConfirmation = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundColor(.yellow)
                    }
                }
            }
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            loadImage()
        }
        .confirmationDialog("Delete Photo?", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                deleteImage()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This photo will be permanently deleted from the app.")
        }
        .alert(exportSuccess ? "Saved!" : "Error", isPresented: $showingExportAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportSuccess ? "Photo saved to your Photo Library." : "Could not save photo. Please check permissions.")
        }
        .sheet(isPresented: $showingShareSheet) {
            if let image = image {
                ShareSheet(items: [image])
            }
        }
    }
    
    // MARK: - Views
    
    private func imageView(_ uiImage: UIImage) -> some View {
        VStack(spacing: 0) {
            // Image with pinch to zoom
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .scaleEffect(scale)
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            scale = lastScale * value
                        }
                        .onEnded { value in
                            lastScale = scale
                            // Limit zoom range
                            if scale < 1.0 {
                                withAnimation {
                                    scale = 1.0
                                    lastScale = 1.0
                                }
                            } else if scale > 5.0 {
                                scale = 5.0
                                lastScale = 5.0
                            }
                        }
                )
                .onTapGesture(count: 2) {
                    withAnimation {
                        if scale > 1.0 {
                            scale = 1.0
                            lastScale = 1.0
                        } else {
                            scale = 2.0
                            lastScale = 2.0
                        }
                    }
                }
            
            // Info bar
            imageInfoBar
        }
    }
    
    private var imageInfoBar: some View {
        VStack(spacing: 8) {
            Divider()
                .background(Color.gray)
            
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "calendar")
                            .foregroundColor(.gray)
                        Text(savedImage.dateString)
                            .foregroundColor(.white)
                    }
                    .font(.subheadline)
                    
                    HStack {
                        Image(systemName: "clock")
                            .foregroundColor(.gray)
                        Text(savedImage.timeString)
                            .foregroundColor(.white)
                    }
                    .font(.subheadline)
                }
                
                Spacer()
                
                if let featureType = savedImage.featureType {
                    featureBadge(featureType)
                } else {
                    Text("Original")
                        .font(.caption)
                        .fontWeight(.medium)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.gray.opacity(0.3))
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .background(Color.black)
    }
    
    private func featureBadge(_ type: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: featureIcon(type))
            Text(type)
        }
        .font(.caption)
        .fontWeight(.medium)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(featureColor(type))
        .foregroundColor(.black)
        .cornerRadius(8)
    }
    
    // MARK: - Methods
    
    private func loadImage() {
        DispatchQueue.global(qos: .userInitiated).async {
            let loadedImage = ImageStorageManager.shared.loadImage(for: savedImage)
            DispatchQueue.main.async {
                image = loadedImage
            }
        }
    }
    
    private func deleteImage() {
        _ = ImageStorageManager.shared.deleteImage(savedImage)
        onDelete()
        dismiss()
    }
    
    private func exportToPhotos() {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            DispatchQueue.main.async {
                if status == .authorized || status == .limited {
                    ImageStorageManager.shared.exportToPhotoLibrary(savedImage) { success, error in
                        DispatchQueue.main.async {
                            exportSuccess = success
                            showingExportAlert = true
                        }
                    }
                } else {
                    exportSuccess = false
                    showingExportAlert = true
                }
            }
        }
    }
    
    private func shareImage() {
        showingShareSheet = true
    }
    
    private func featureIcon(_ type: String) -> String {
        switch type.lowercased() {
        case "skin": return "face.smiling"
        case "hair": return "person.crop.circle"
        case "teeth": return "mouth"
        case "glasses": return "eyeglasses"
        default: return "photo"
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

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Preview

struct ImageDetailView_Previews: PreviewProvider {
    static var previews: some View {
        ImageDetailView(
            savedImage: SavedImage(
                id: UUID(),
                filename: "test.jpg",
                captureDate: Date(),
                featureType: "Skin"
            ),
            onDelete: {}
        )
    }
}
