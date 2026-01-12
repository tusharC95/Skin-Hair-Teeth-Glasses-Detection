/*
 BannerAdView.swift
 SSMUtility

 SwiftUI + UIKit reusable AdMob banner.
 */

import SwiftUI
import GoogleMobileAds
import Sentry

private let logger = SentrySDK.logger

// MARK: - SwiftUI wrapper

struct AdMobBannerView: UIViewRepresentable {
    let adUnitID: String

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> BannerView {
        let banner = BannerView(adSize: AdSizeBanner)
        banner.adUnitID = adUnitID
        banner.rootViewController = UIApplication.shared.topMostViewController
        banner.delegate = context.coordinator
        banner.load(AdMobManager.shared.makeRequest())
        return banner
    }

    func updateUIView(_ uiView: BannerView, context: Context) {
        // no-op
    }

    final class Coordinator: NSObject, BannerViewDelegate {
        func bannerViewDidReceiveAd(_ bannerView: BannerView) {
            logger.debug("AdMob banner loaded")
        }

        func bannerView(_ bannerView: BannerView, didFailToReceiveAdWithError error: Error) {
            logger.warn("AdMob banner failed to load", attributes: ["error": error.localizedDescription])
        }
    }
}

// MARK: - UIKit container

final class AdMobBannerContainerView: UIView {
    private let bannerView = BannerView(adSize: AdSizeBanner)
    private var didLoad = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        backgroundColor = .clear
        bannerView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bannerView)

        NSLayoutConstraint.activate([
            bannerView.centerXAnchor.constraint(equalTo: centerXAnchor),
            bannerView.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    func load(adUnitID: String, rootViewController: UIViewController) {
        guard !didLoad else { return }
        didLoad = true

        bannerView.adUnitID = adUnitID
        bannerView.rootViewController = rootViewController
        bannerView.load(AdMobManager.shared.makeRequest())
    }
}

// MARK: - UIApplication helpers

private extension UIApplication {
    var topMostViewController: UIViewController? {
        let root = connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first(where: { $0.isKeyWindow })?
            .rootViewController
        return root?.topMostPresentedViewController ?? root
    }
}

private extension UIViewController {
    var topMostPresentedViewController: UIViewController {
        presentedViewController?.topMostPresentedViewController ?? self
    }
}

