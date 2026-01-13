/*
 SentryErrorReporter.swift
 SSMUtility

 Utility class for reporting errors to Sentry.
*/

import Foundation
import Sentry

// MARK: - SentryErrorReporter

final class SentryErrorReporter {
    
    static let shared = SentryErrorReporter()
    
    private init() {}
    
    // MARK: - Error Reporting
    
    /// Report an error to Sentry
    /// - Parameters:
    ///   - error: The error to report
    ///   - context: Additional context about where the error occurred
    ///   - extras: Additional data to attach to the error
    func reportError(
        _ error: Error,
        context: String? = nil,
        extras: [String: Any]? = nil
    ) {
        SentrySDK.capture(error: error) { scope in
            if let context = context {
                scope.setContext(value: ["location": context], key: "error_context")
            }
            if let extras = extras {
                for (key, value) in extras {
                    scope.setExtra(value: value, key: key)
                }
            }
        }
    }
}
