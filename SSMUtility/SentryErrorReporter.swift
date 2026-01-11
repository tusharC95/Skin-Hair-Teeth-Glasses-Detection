/*
 SentryErrorReporter.swift
 SSMUtility

 Utility class for reporting errors and events to Sentry.
*/

import Foundation
import Sentry

// MARK: - Error Severity

enum ErrorSeverity {
    case debug
    case info
    case warning
    case error
    case fatal
    
    var sentryLevel: SentryLevel {
        switch self {
        case .debug: return .debug
        case .info: return .info
        case .warning: return .warning
        case .error: return .error
        case .fatal: return .fatal
        }
    }
}

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
    
    /// Report a message to Sentry
    /// - Parameters:
    ///   - message: The message to report
    ///   - severity: The severity level
    ///   - extras: Additional data to attach
    func reportMessage(
        _ message: String,
        severity: ErrorSeverity = .info,
        extras: [String: Any]? = nil
    ) {
        SentrySDK.capture(message: message) { scope in
            scope.setLevel(severity.sentryLevel)
            if let extras = extras {
                for (key, value) in extras {
                    scope.setExtra(value: value, key: key)
                }
            }
        }
    }
    
    // MARK: - Breadcrumbs
    
    /// Add a breadcrumb for debugging
    /// - Parameters:
    ///   - category: Category of the breadcrumb (e.g., "camera", "gallery", "storage")
    ///   - message: Description of what happened
    ///   - level: Severity level
    ///   - data: Additional data
    func addBreadcrumb(
        category: String,
        message: String,
        level: ErrorSeverity = .info,
        data: [String: Any]? = nil
    ) {
        let crumb = Breadcrumb(level: level.sentryLevel, category: category)
        crumb.message = message
        if let data = data {
            crumb.data = data
        }
        SentrySDK.addBreadcrumb(crumb)
    }
    
    // MARK: - User Context
    
    /// Set the current user for error tracking
    /// - Parameter userId: Unique user identifier (use anonymous ID if no login)
    func setUser(userId: String) {
        let user = User(userId: userId)
        SentrySDK.setUser(user)
    }
    
    /// Clear user context
    func clearUser() {
        SentrySDK.setUser(nil)
    }
    
    // MARK: - Performance Monitoring
    
    /// Start a performance transaction
    /// - Parameters:
    ///   - name: Transaction name (e.g., "Photo Capture")
    ///   - operation: Operation type (e.g., "camera.capture")
    /// - Returns: Transaction span that should be finished when operation completes
    func startTransaction(name: String, operation: String) -> Span? {
        return SentrySDK.startTransaction(name: name, operation: operation)
    }
    
    /// Start a child span within a transaction
    /// - Parameters:
    ///   - parent: Parent transaction or span
    ///   - operation: Operation name
    ///   - description: Description of the operation
    /// - Returns: Child span
    func startSpan(parent: Span, operation: String, description: String) -> Span {
        return parent.startChild(operation: operation, description: description)
    }
}

// MARK: - Convenience Extensions

extension Error {
    /// Report this error to Sentry
    func reportToSentry(context: String? = nil, extras: [String: Any]? = nil) {
        SentryErrorReporter.shared.reportError(self, context: context, extras: extras)
    }
}
