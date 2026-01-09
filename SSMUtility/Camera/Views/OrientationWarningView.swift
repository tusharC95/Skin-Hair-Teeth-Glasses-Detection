/*
 OrientationWarningView.swift
 SSMUtility

 UIKit view displaying a warning when device is in landscape orientation.
*/

import UIKit

class OrientationWarningView: UIView {
    
    // MARK: - UI Elements
    
    private let stackView = UIStackView()
    private let iconImageView = UIImageView()
    private let titleLabel = UILabel()
    private let messageLabel = UILabel()
    
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
        backgroundColor = UIColor.black.withAlphaComponent(0.85)
        
        setupStackView()
        setupIcon()
        setupTitle()
        setupMessage()
        setupConstraints()
        startIconAnimation()
    }
    
    private func setupStackView() {
        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.spacing = 16
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)
    }
    
    private func setupIcon() {
        let iconConfig = UIImage.SymbolConfiguration(pointSize: 60, weight: .medium)
        iconImageView.image = UIImage(systemName: "iphone.gen3", withConfiguration: iconConfig)
        iconImageView.tintColor = .systemYellow
        iconImageView.contentMode = .scaleAspectFit
        stackView.addArrangedSubview(iconImageView)
    }
    
    private func setupTitle() {
        titleLabel.text = "Rotate to Portrait"
        titleLabel.font = .systemFont(ofSize: 22, weight: .bold)
        titleLabel.textColor = .white
        stackView.addArrangedSubview(titleLabel)
    }
    
    private func setupMessage() {
        messageLabel.text = "Please hold your device upright\nto capture photos"
        messageLabel.font = .systemFont(ofSize: 16)
        messageLabel.textColor = .white.withAlphaComponent(0.8)
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0
        stackView.addArrangedSubview(messageLabel)
    }
    
    private func setupConstraints() {
        NSLayoutConstraint.activate([
            stackView.centerXAnchor.constraint(equalTo: centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
    
    private func startIconAnimation() {
        let rotationAnimation = CABasicAnimation(keyPath: "transform.rotation.z")
        rotationAnimation.fromValue = -CGFloat.pi / 4
        rotationAnimation.toValue = 0
        rotationAnimation.duration = 0.6
        rotationAnimation.autoreverses = true
        rotationAnimation.repeatCount = .infinity
        iconImageView.layer.add(rotationAnimation, forKey: "rotation")
    }
    
    // MARK: - Public Methods
    
    func show(in parentView: UIView, animated: Bool = true) {
        translatesAutoresizingMaskIntoConstraints = false
        parentView.addSubview(self)
        
        NSLayoutConstraint.activate([
            leadingAnchor.constraint(equalTo: parentView.leadingAnchor),
            trailingAnchor.constraint(equalTo: parentView.trailingAnchor),
            topAnchor.constraint(equalTo: parentView.topAnchor),
            bottomAnchor.constraint(equalTo: parentView.bottomAnchor)
        ])
        
        if animated {
            alpha = 0
            UIView.animate(withDuration: 0.3) {
                self.alpha = 1
            }
        }
    }
    
    func hide(animated: Bool = true, completion: (() -> Void)? = nil) {
        if animated {
            UIView.animate(withDuration: 0.3, animations: {
                self.alpha = 0
            }) { _ in
                self.removeFromSuperview()
                completion?()
            }
        } else {
            removeFromSuperview()
            completion?()
        }
    }
}
