//
//  AppDelegate.swift
//  SSMUtility
//
//  Created by Tushar Chitnavis on 25/12/21.
//

import UIKit
import Sentry
import GoogleMobileAds

private let logger = SentrySDK.logger

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        
        // Initialize Sentry
        SentrySDK.start { options in
            options.dsn = "https://496cae644f48673b11f7de05115e38d0@o4510688986202112.ingest.us.sentry.io/4510688993673216"
            options.enableLogs = true
            options.sendDefaultPii = false
            // Enable debug mode during development (disable in production)
            #if DEBUG
            options.debug = true
            #endif
            
            // Set environment
            #if DEBUG
            options.environment = "development"
            #else
            options.environment = "production"
            #endif
            
            // Enable automatic performance monitoring
            options.tracesSampleRate = 1.0
            
            // Enable automatic session tracking
            options.enableAutoSessionTracking = true
            
            // Attach stack traces to all messages
            options.attachStacktrace = true
            
            // Enable App Hang detection (UI freezes > 2 seconds)
            options.enableAppHangTracking = true
            options.appHangTimeoutInterval = 2
            
            // Enable automatic breadcrumb collection
            options.enableAutoBreadcrumbTracking = true
            
            // Enable crash reporting
            options.enableCrashHandler = true
            
            // Set release version
            if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
               let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
                options.releaseName = "com.unmasklab.SSMUtility@\(version)+\(build)"
            }
        }
        
        // Log app launch
        logger.info("App launched successfully")

        // Initialize Google Mobile Ads (AdMob)
        AdMobManager.shared.configure()
        
        return true
    }

    // MARK: UISceneSession Lifecycle

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        // Called when a new scene session is being created.
        // Use this method to select a configuration to create the new scene with.
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
        // Called when the user discards a scene session.
        // If any sessions were discarded while the application was not running, this will be called shortly after application:didFinishLaunchingWithOptions.
        // Use this method to release any resources that were specific to the discarded scenes, as they will not return.
    }


}

