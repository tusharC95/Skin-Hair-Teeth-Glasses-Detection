/*
 ImageDetailView.swift
 SSMUtility

 SwiftUI view for viewing a single image with export/delete options.
 UI layer - delegates business logic to ImageDetailViewModel.
*/

import SwiftUI
import Photos

struct ImageDetailView: View {
    @StateObject private var viewModel: ImageDetailViewModel
    @Environment(\.dismiss) private var dismiss
    
    // Zoom state (kept in view as purely UI-related)
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    
    // Pan/drag state
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    
    // MARK: - Initialization
    
    init(savedImage: SavedImage, onDelete: @escaping () -> Void) {
        _viewModel = StateObject(wrappedValue: ImageDetailViewModel(savedImage: savedImage, onDelete: onDelete))
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                if viewModel.isLoading {
                    loadingView
                } else if let image = viewModel.image {
                    imageContentView(image)
                } else {
                    errorView
                }
            }
            .navigationTitle(viewModel.navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                imageInfoBar
                AdMobBannerView(adUnitID: AdMobManager.shared.bannerAdUnitID)
                    .frame(height: 50)
                    .padding(.vertical, 8)
            }
            .background(Color.black)
        }
        .onAppear {
            viewModel.loadImage()
        }
        .confirmationDialog("Delete Photo?", isPresented: $viewModel.showingDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if viewModel.deleteImage() {
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This photo will be permanently deleted from the app.")
        }
        .alert("Error", isPresented: $viewModel.showingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage)
        }
        .alert(viewModel.exportSuccess ? "Saved!" : "Error", isPresented: $viewModel.showingExportAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.exportMessage)
        }
        .sheet(isPresented: $viewModel.showingShareSheet) {
            if let image = viewModel.image {
                ShareSheet(items: [image])
            }
        }
    }
    
    // MARK: - Toolbar
    
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Button("Close") {
                dismiss()
            }
            .foregroundColor(.yellow)
        }
        
        ToolbarItem(placement: .navigationBarTrailing) {
            actionMenu
        }
    }
    
    private var actionMenu: some View {
        Menu {
            Button {
                viewModel.shareImage()
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            
            Button {
                viewModel.exportToPhotos()
            } label: {
                Label("Save to Photos", systemImage: "photo.on.rectangle")
            }
            
            Divider()
            
            Button(role: .destructive) {
                viewModel.confirmDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .foregroundColor(.yellow)
        }
    }
    
    // MARK: - Views
    
    private var loadingView: some View {
        ProgressView()
            .tint(.yellow)
            .scaleEffect(1.5)
    }
    
    private var errorView: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 50))
                .foregroundColor(.gray)
            Text("Unable to load image")
                .foregroundColor(.gray)
        }
    }
    
    private func imageContentView(_ uiImage: UIImage) -> some View {
        GeometryReader { geo in
            zoomableImage(uiImage)
                .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
                .clipped()
        }
    }
    
    private func zoomableImage(_ uiImage: UIImage) -> some View {
        Image(uiImage: uiImage)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .scaleEffect(scale)
            .offset(offset)
            .gesture(combinedGesture)
            .onTapGesture(count: 2) {
                handleDoubleTap()
            }
    }
    
    private var combinedGesture: some Gesture {
        SimultaneousGesture(zoomGesture, dragGesture)
    }
    
    private var zoomGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                scale = lastScale * value
            }
            .onEnded { _ in
                lastScale = scale
                constrainZoom()
            }
    }
    
    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                // Only allow dragging when zoomed in
                guard scale > 1.0 else { return }
                offset = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                lastOffset = offset
                constrainOffset()
            }
    }
    
    private func handleDoubleTap() {
        withAnimation {
            if scale > 1.0 {
                scale = 1.0
                lastScale = 1.0
                offset = .zero
                lastOffset = .zero
            } else {
                scale = 2.0
                lastScale = 2.0
            }
        }
    }
    
    private func constrainZoom() {
        if scale < 1.0 {
            withAnimation {
                scale = 1.0
                lastScale = 1.0
                offset = .zero
                lastOffset = .zero
            }
        } else if scale > 5.0 {
            scale = 5.0
            lastScale = 5.0
        }
    }
    
    private func constrainOffset() {
        // Reset offset if scale is back to normal
        if scale <= 1.0 {
            withAnimation {
                offset = .zero
                lastOffset = .zero
            }
        }
    }
    
    private var imageInfoBar: some View {
        VStack(spacing: 8) {
            Divider()
                .background(Color.gray)
            
            HStack {
                imageMetadata
                Spacer()
                featureBadge
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .background(Color.black)
    }
    
    private var imageMetadata: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "calendar")
                    .foregroundColor(.gray)
                Text(viewModel.dateString)
                    .foregroundColor(.white)
            }
            .font(.subheadline)
            
            HStack {
                Image(systemName: "clock")
                    .foregroundColor(.gray)
                Text(viewModel.timeString)
                    .foregroundColor(.white)
            }
            .font(.subheadline)
        }
    }
    
    @ViewBuilder
    private var featureBadge: some View {
        if let featureType = viewModel.featureType {
            FeatureBadgeView(
                type: featureType,
                icon: viewModel.featureIcon(for: featureType),
                colorType: viewModel.featureColorName(for: featureType)
            )
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
}

// MARK: - Feature Badge View

struct FeatureBadgeView: View {
    let type: String
    let icon: String
    let colorType: FeatureColorType
    
    private var backgroundColor: Color {
        switch colorType {
        case .skin: return .yellow
        case .hair: return .orange
        case .teeth: return Color(white: 0.85)
        case .glasses: return .cyan
        case .other: return .gray
        }
    }
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            Text(type)
        }
        .font(.caption)
        .fontWeight(.medium)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(backgroundColor)
        .foregroundColor(.black)
        .cornerRadius(8)
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
