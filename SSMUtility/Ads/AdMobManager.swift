/*
 AdMobManager.swift
 SSMUtility

 Centralized AdMob configuration and ad unit IDs.
 */

import Foundation
import GoogleMobileAds
import Sentry

private let logger = SentrySDK.logger

final class AdMobManager {
    static let shared = AdMobManager()

    private init() {}

    private(set) var isConfigured = false

    /// Call once during app launch.
    func configure() {
        guard !isConfigured else { return }

        // SDK v12+ Swift API renames remove the "GAD" prefix (see migration guide).
        MobileAds.shared.start(completionHandler: { status in
            logger.info("AdMob started", attributes: [
                "adapterCount": status.adapterStatusesByClassName.count
            ])
        })

        isConfigured = true
    }

    /// Banner Ad Unit ID.
    /// - Uses `ADMOB_BANNER_AD_UNIT_ID` from Info.plist if present.
    /// - Falls back to Google test banner unit ID.
    var bannerAdUnitID: String {
        if let id = Bundle.main.object(forInfoDictionaryKey: "ADMOB_BANNER_AD_UNIT_ID") as? String,
           !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return id
        }
        // Google test banner ad unit id
        return "ca-app-pub-3940256099942544/2934735716"
    }

    func makeRequest() -> Request {
        let request = Request()
        return request
    }
}

