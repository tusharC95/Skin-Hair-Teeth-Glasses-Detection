/*
 FeatureSelectionView.swift
 SSMUtility

 SwiftUI view for selecting facial features (Skin, Hair, Teeth, Glasses).
 Uses iOS 26+ Liquid Glass design.
*/

import SwiftUI
import UIKit
import AVFoundation

// MARK: - FacialFeature Extension for SwiftUI

extension FacialFeature: Identifiable {
    var id: String { rawValue }
}

// MARK: - FeatureSelectionView

struct FeatureSelectionView: View {
    @Binding var selectedFeatures: Set<FacialFeature>
    @Binding var allSelected: Bool
    
    var onFeatureSelected: ((FacialFeature) -> Void)?
    var onAllSelected: (() -> Void)?
    
    var body: some View {
        // iOS 26+: Group glass elements in a container so they can render efficiently
        // and blend into each other (the "liquid" effect).
        GlassEffectContainer {
            selectionStack
                .padding(12)
        }
    }

    private var selectionStack: some View {
        // Match UIKit `UIStackView` (spacing = 8, distribution = .fillEqually)
        HStack(spacing: 8) {
            // All Button
            FeatureButton(
                title: "All",
                icon: "checkmark.circle.fill",
                isSelected: allSelected
            ) {
                triggerHapticFeedback()
                onAllSelected?()
            }

            // Feature Buttons
            ForEach(FacialFeature.allCases, id: \.self) { feature in
                FeatureButton(
                    title: feature.rawValue,
                    icon: feature.icon,
                    isSelected: selectedFeatures.contains(feature)
                ) {
                    triggerHapticFeedback()
                    onFeatureSelected?(feature)
                }
            }
        }
    }
    
    private func triggerHapticFeedback() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }
}

// MARK: - FeatureButton with Liquid Glass Effect

struct FeatureButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    
    /// Tint color based on selection state
    private var tintColor: Color {
        isSelected ? Color.yellow.opacity(0.8) : Color.white.opacity(0.3)
    }
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
            }
            // Match UIKit filled button: equal width in row, medium corners, compact height.
            .frame(maxWidth: .infinity, minHeight: 56)
            .foregroundColor(isSelected ? .black : .white)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.tint(tintColor).interactive())
        // Match UIKit `UIButton.Configuration.cornerStyle = .medium`
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - UIKit Hosting Wrapper

/// A UIView wrapper for hosting the SwiftUI FeatureSelectionView in UIKit view hierarchies.
class FeatureSelectionHostingView: UIView {
    
    // MARK: - Properties
    
    private var hostingController: UIHostingController<FeatureSelectionView>?
    private var selectedFeatures: Set<FacialFeature> = Set(FacialFeature.allCases)
    private var allSelected: Bool = true
    
    var onFeatureSelected: ((FacialFeature) -> Void)?
    var onAllSelected: (() -> Void)?
    
    // MARK: - Initialization
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupHostingController()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupHostingController()
    }
    
    // MARK: - Setup
    
    private func setupHostingController() {
        backgroundColor = .clear
        
        let swiftUIView = FeatureSelectionView(
            selectedFeatures: Binding(
                get: { [weak self] in self?.selectedFeatures ?? [] },
                set: { [weak self] in self?.selectedFeatures = $0 }
            ),
            allSelected: Binding(
                get: { [weak self] in self?.allSelected ?? false },
                set: { [weak self] in self?.allSelected = $0 }
            ),
            onFeatureSelected: { [weak self] feature in
                self?.onFeatureSelected?(feature)
            },
            onAllSelected: { [weak self] in
                self?.onAllSelected?()
            }
        )
        
        let hostingController = UIHostingController(rootView: swiftUIView)
        hostingController.view.backgroundColor = .clear
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        
        addSubview(hostingController.view)
        
        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        
        self.hostingController = hostingController
    }
    
    // MARK: - Public Methods
    
    func updateButtonStates(selectedFeatures: Set<FacialFeature>, allSelected: Bool) {
        self.selectedFeatures = selectedFeatures
        self.allSelected = allSelected
        
        // Recreate the SwiftUI view with updated bindings
        let swiftUIView = FeatureSelectionView(
            selectedFeatures: Binding(
                get: { [weak self] in self?.selectedFeatures ?? [] },
                set: { [weak self] in self?.selectedFeatures = $0 }
            ),
            allSelected: Binding(
                get: { [weak self] in self?.allSelected ?? false },
                set: { [weak self] in self?.allSelected = $0 }
            ),
            onFeatureSelected: { [weak self] feature in
                self?.onFeatureSelected?(feature)
            },
            onAllSelected: { [weak self] in
                self?.onAllSelected?()
            }
        )
        
        hostingController?.rootView = swiftUIView
    }
}

// MARK: - Preview

#Preview {
    @Previewable @State var selectedFeatures: Set<FacialFeature> = []
    @Previewable @State var allSelected: Bool = false
    
    ZStack {
        Color.black
            .ignoresSafeArea()
        
        VStack {
            Spacer()
            
            FeatureSelectionView(
                selectedFeatures: $selectedFeatures,
                allSelected: $allSelected,
                onFeatureSelected: { feature in
                    withAnimation(.spring(duration: 0.3)) {
                        if selectedFeatures.contains(feature) {
                            selectedFeatures.remove(feature)
                        } else {
                            selectedFeatures.insert(feature)
                        }
                        allSelected = selectedFeatures.count == FacialFeature.allCases.count
                    }
                },
                onAllSelected: {
                    withAnimation(.spring(duration: 0.3)) {
                        if allSelected {
                            allSelected = false
                            selectedFeatures.removeAll()
                        } else {
                            allSelected = true
                            selectedFeatures = Set(FacialFeature.allCases)
                        }
                    }
                }
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 40)
        }
    }
}
