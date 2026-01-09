/*
 FeatureSelectionView.swift
 SSMUtility

 UIKit view for selecting facial features (Skin, Hair, Teeth, Glasses).
*/

import UIKit

// MARK: - Protocol

protocol FeatureSelectionViewDelegate: AnyObject {
    func featureSelectionView(_ view: FeatureSelectionView, didSelectFeature feature: FacialFeature)
    func featureSelectionViewDidSelectAll(_ view: FeatureSelectionView)
}

// MARK: - FeatureSelectionView

class FeatureSelectionView: UIView {
    
    // MARK: - Properties
    
    weak var delegate: FeatureSelectionViewDelegate?
    
    private var featureButtons: [FacialFeature: UIButton] = [:]
    private var allButton: UIButton!
    private let stackView = UIStackView()
    
    // MARK: - Initialization
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }
    
    // MARK: - Setup
    
    private func setupView() {
        backgroundColor = UIColor.black.withAlphaComponent(0.6)
        layer.cornerRadius = 16
        
        setupStackView()
        setupAllButton()
        setupFeatureButtons()
        setupConstraints()
    }
    
    private func setupStackView() {
        stackView.axis = .horizontal
        stackView.distribution = .fillEqually
        stackView.spacing = 8
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)
    }
    
    private func setupAllButton() {
        allButton = createButton(title: "All", icon: "checkmark.circle.fill")
        allButton.addTarget(self, action: #selector(allButtonTapped), for: .touchUpInside)
        stackView.addArrangedSubview(allButton)
    }
    
    private func setupFeatureButtons() {
        for feature in FacialFeature.allCases {
            let button = createButton(title: feature.rawValue, icon: feature.icon)
            button.tag = FacialFeature.allCases.firstIndex(of: feature)!
            button.addTarget(self, action: #selector(featureButtonTapped(_:)), for: .touchUpInside)
            featureButtons[feature] = button
            stackView.addArrangedSubview(button)
        }
    }
    
    private func setupConstraints() {
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            stackView.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8)
        ])
    }
    
    // MARK: - Button Factory
    
    private func createButton(title: String, icon: String) -> UIButton {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        
        var config = UIButton.Configuration.filled()
        config.title = title
        config.image = UIImage(systemName: icon)
        config.imagePlacement = .top
        config.imagePadding = 4
        config.cornerStyle = .medium
        config.baseBackgroundColor = UIColor.darkGray
        config.baseForegroundColor = .white
        
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = UIFont.systemFont(ofSize: 10, weight: .medium)
            return outgoing
        }
        
        button.configuration = config
        return button
    }
    
    // MARK: - Actions
    
    @objc private func allButtonTapped() {
        triggerHapticFeedback()
        delegate?.featureSelectionViewDidSelectAll(self)
    }
    
    @objc private func featureButtonTapped(_ sender: UIButton) {
        triggerHapticFeedback()
        let feature = FacialFeature.allCases[sender.tag]
        delegate?.featureSelectionView(self, didSelectFeature: feature)
    }
    
    private func triggerHapticFeedback() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }
    
    // MARK: - Public Methods
    
    func updateButtonStates(selectedFeatures: Set<FacialFeature>, allSelected: Bool) {
        updateButtonAppearance(allButton, isSelected: allSelected)
        
        for feature in FacialFeature.allCases {
            if let button = featureButtons[feature] {
                updateButtonAppearance(button, isSelected: selectedFeatures.contains(feature))
            }
        }
    }
    
    private func updateButtonAppearance(_ button: UIButton, isSelected: Bool) {
        var config = button.configuration
        if isSelected {
            config?.baseBackgroundColor = UIColor.systemYellow
            config?.baseForegroundColor = .black
        } else {
            config?.baseBackgroundColor = UIColor.darkGray.withAlphaComponent(0.8)
            config?.baseForegroundColor = .white.withAlphaComponent(0.6)
        }
        button.configuration = config
    }
}
