//
//  DamusSentry.swift
//  damus
//
import Sentry

/// Namespace for Damus Sentry startup, capture helpers, and sensitive-data scrubbing.
///
/// This type centralizes Sentry configuration during app startup and provides
/// privacy-preserving helpers used before telemetry leaves the device.
struct DamusSentry {
    
    /// Returns the Sentry environment name for the current build configuration.
    ///
    /// Debug builds are tagged separately so local development traffic does not
    /// get grouped together with production events in Sentry.
    ///
    /// - Returns: The Sentry environment name for the current build.
    static func environmentName() -> String {
        #if DEBUG
        return "debug"
        #else
        return "production"
        #endif
    }
    
    /// Starts Sentry with Damus-specific configuration when telemetry is enabled.
    ///
    /// This centralizes Sentry startup so the app entry point stays small and all
    /// telemetry-related configuration lives in one place.
    static func startIfEnabled() {
        guard GlobalSettingsStore.shared.enable_sentry_telemetry else {
            Log.info("Sentry telemetry disabled by user preference", for: .app_lifecycle)
            return
        }
        
        SentrySDK.start { options in
            options.dsn = "https://9be03ae55b9c1b55feb599f470772deb@o4511304644558848.ingest.us.sentry.io/4511304645738496"
            options.environment = environmentName()
            
            // Adds IP for users.
            // For more information, visit: https://docs.sentry.io/platforms/apple/data-management/data-collected/
            options.sendDefaultPii = false
            
            // Set tracesSampleRate to 1.0 to capture 100% of transactions for performance monitoring.
            options.tracesSampleRate = 0.5
            
            // Configure profiling. Visit https://docs.sentry.io/platforms/apple/profiling/ to learn more.
            options.configureProfiling = {
                $0.sessionSampleRate = 0.5
                $0.lifecycle = .trace
            }
            
            // Scrub sensitive data before sending to Sentry.
            options.beforeSend = { event in
                return scrubSensitiveData(in: event)
            }
            
            options.beforeBreadcrumb = { breadcrumb in
                return scrubSensitiveDataInBreadcrumb(breadcrumb)
            }
            
            options.beforeSendSpan = { span in
                return scrubSensitiveDataInSpan(span)
            }
            
            // Uncomment the following lines to add more data to your events
            // options.attachScreenshot = true // This adds a screenshot to the error events
            // options.attachViewHierarchy = true // This adds the view hierarchy to the error events
            
            // Enable experimental logging features
            // options.experimental.enableLogs = true
        }
    }
    
    /// Safely captures an error to Sentry only if the user has enabled telemetry.
    ///
    /// This is a convenience wrapper around `SentrySDK.capture(error:)` that respects
    /// the user's privacy preference from GlobalSettingsStore.
    ///
    /// - Parameters:
    ///   - error: The error to capture
    ///   - scopeBlock: Optional block to configure the scope for this capture
    static func captureSentryError(_ error: Error, scopeBlock: ((Scope) -> Void)? = nil) {
        guard GlobalSettingsStore.shared.enable_sentry_telemetry else { return }
        if let scopeBlock = scopeBlock {
            SentrySDK.capture(error: error, block: scopeBlock)
        } else {
            SentrySDK.capture(error: error)
        }
    }
    
    /// Safely captures a message to Sentry only if the user has enabled telemetry.
    ///
    /// This is a convenience wrapper around `SentrySDK.capture(message:)` that respects
    /// the user's privacy preference from GlobalSettingsStore.
    ///
    /// - Parameters:
    ///   - message: The message to capture
    ///   - scopeBlock: Optional block to configure the scope for this capture
    static func captureSentryMessage(_ message: String, scopeBlock: ((Scope) -> Void)? = nil) {
        guard GlobalSettingsStore.shared.enable_sentry_telemetry else { return }
        if let scopeBlock = scopeBlock {
            SentrySDK.capture(message: message, block: scopeBlock)
        } else {
            SentrySDK.capture(message: message)
        }
    }
    
    /// Scrubs sensitive data from Sentry events before they are sent.
    ///
    /// This method removes or redacts:
    /// - Nostr private keys (nsec1...)
    /// - Nostr public keys (npub1...)
    /// - Nostr note IDs (note1...)
    /// - Nostr note events with hints (nevent1...)
    /// - Nostr profiles with hints (nprofile1...)
    /// - Nostr addressable events (naddr1...)
    /// - Nostr relay references (nrelay1...)
    /// - Hex-encoded keys (64-character hex strings)
    /// - Email addresses
    ///
    /// - Parameter event: The Sentry event to scrub
    /// - Returns: The scrubbed event, or nil to discard the event
    static func scrubSensitiveData(in event: Event) -> Event? {
        // Scrub message - create new SentryMessage with scrubbed content
        if let messageText = event.message?.formatted {
            let scrubbedText = scrubString(messageText)
            event.message = SentryMessage(formatted: scrubbedText)
        }
        
        // Scrub exception messages and values
        if let exceptions = event.exceptions {
            for exception in exceptions {
                if let value = exception.value {
                    exception.value = scrubString(value)
                }
                if let mechanism = exception.mechanism, let description = mechanism.desc {
                    mechanism.desc = scrubString(description)
                }
                // Scrub stack trace
                if let stacktrace = exception.stacktrace {
                    scrubStacktrace(stacktrace)
                }
            }
        }
        
        // Scrub threads
        if let threads = event.threads {
            for thread in threads {
                if let stacktrace = thread.stacktrace {
                    scrubStacktrace(stacktrace)
                }
            }
        }
        
        // Scrub context data
        if var context = event.context as? [String: Any] {
            scrubDictionary(&context)
            event.context = context as? [String: [String: Any]]
        }
        
        // Scrub extra data
        if var extra = event.extra {
            scrubDictionary(&extra)
            event.extra = extra
        }
        
        // Scrub tags
        if let tags = event.tags {
            for (key, value) in tags {
                event.tags?[key] = scrubString(value)
            }
        }
        
        // Scrub user data
        if let user = event.user {
            if let email = user.email {
                user.email = scrubEmail(email)
            }
            if let userId = user.userId {
                user.userId = scrubString(userId)
            }
            if let username = user.username {
                user.username = scrubString(username)
            }
            if var data = user.data {
                scrubDictionary(&data)
                user.data = data
            }
        }
        
        // Scrub request data
        if let request = event.request {
            if let url = request.url {
                request.url = scrubString(url)
            }
            if let queryString = request.queryString {
                request.queryString = scrubString(queryString)
            }
            if var headers = request.headers as? [String: Any] {
                scrubDictionary(&headers)
                request.headers = headers as? [String: String]
            }
        }
        
        return event
    }
    
    /// Scrubs sensitive data from Sentry breadcrumbs.
    ///
    /// - Parameter breadcrumb: The breadcrumb to scrub
    /// - Returns: The scrubbed breadcrumb, or nil to discard it
    static func scrubSensitiveDataInBreadcrumb(_ breadcrumb: Breadcrumb) -> Breadcrumb? {
        // Scrub message
        if let message = breadcrumb.message {
            breadcrumb.message = scrubString(message)
        }
        
        // Scrub data
        if var data = breadcrumb.data {
            scrubDictionary(&data)
            breadcrumb.data = data
        }
        
        return breadcrumb
    }
    
    /// Scrubs sensitive data from Sentry spans.
    ///
    /// Spans represent units of work in performance tracing (e.g., network requests, database queries).
    /// If a span contains sensitive data, it's dropped entirely rather than sent with potentially unscrubbed data.
    ///
    /// - Parameter span: The span to scrub
    /// - Returns: The scrubbed span, or nil to discard it
    static func scrubSensitiveDataInSpan(_ span: Span) -> Span? {
        // Check span description for sensitive data
        if let spanDescription = span.spanDescription {
            if containsSensitiveData(spanDescription) {
                // Drop the entire span if it contains sensitive data
                return nil
            }
        }
        
        // Check span data for sensitive data (read-only, can't scrub)
        if let data = span.data as? [String: Any] {
            if containsSensitiveDataInDictionary(data) {
                return nil
            }
        }
        
        // Check span tags for sensitive data (read-only, can't scrub)
        for (_, value) in span.tags {
            if containsSensitiveData(value) {
                return nil
            }
        }
        
        return span
    }
    
    /// Checks if a string contains sensitive data patterns.
    ///
    /// - Parameter string: The string to check
    /// - Returns: True if the string contains sensitive data
    private static func containsSensitiveData(_ string: String) -> Bool {
        // Check for nsec (private keys)
        if string.range(of: "nsec1[a-zA-Z0-9]{58,}", options: .regularExpression) != nil {
            return true
        }
        
        // Check for npub (public keys)
        if string.range(of: "npub1[a-zA-Z0-9]{58,}", options: .regularExpression) != nil {
            return true
        }
        
        // Check for note IDs
        if string.range(of: "note1[a-zA-Z0-9]{58,}", options: .regularExpression) != nil {
            return true
        }
        
        // Check for nevent
        if string.range(of: "nevent1[a-zA-Z0-9]{58,}", options: .regularExpression) != nil {
            return true
        }
        
        // Check for nprofile
        if string.range(of: "nprofile1[a-zA-Z0-9]{58,}", options: .regularExpression) != nil {
            return true
        }
        
        // Check for naddr
        if string.range(of: "naddr1[a-zA-Z0-9]{58,}", options: .regularExpression) != nil {
            return true
        }
        
        // Check for nrelay
        if string.range(of: "nrelay1[a-zA-Z0-9]+", options: .regularExpression) != nil {
            return true
        }
        
        // Check for hex keys (64-character hex strings)
        if string.range(of: "\\b[0-9a-fA-F]{64}\\b", options: .regularExpression) != nil {
            return true
        }
        
        // Check for email addresses
        if string.range(of: "[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}", options: .regularExpression) != nil {
            return true
        }
        
        return false
    }
    
    /// Checks if a dictionary contains sensitive data.
    ///
    /// - Parameter dictionary: The dictionary to check
    /// - Returns: True if the dictionary contains sensitive data
    private static func containsSensitiveDataInDictionary(_ dictionary: [String: Any]) -> Bool {
        for (_, value) in dictionary {
            if let stringValue = value as? String {
                if containsSensitiveData(stringValue) {
                    return true
                }
            } else if let nestedDict = value as? [String: Any] {
                if containsSensitiveDataInDictionary(nestedDict) {
                    return true
                }
            } else if let array = value as? [Any] {
                if containsSensitiveDataInArray(array) {
                    return true
                }
            }
        }
        return false
    }
    
    /// Checks if an array contains sensitive data.
    ///
    /// - Parameter array: The array to check
    /// - Returns: True if the array contains sensitive data
    private static func containsSensitiveDataInArray(_ array: [Any]) -> Bool {
        for item in array {
            if let stringValue = item as? String {
                if containsSensitiveData(stringValue) {
                    return true
                }
            } else if let dictValue = item as? [String: Any] {
                if containsSensitiveDataInDictionary(dictValue) {
                    return true
                }
            } else if let arrayValue = item as? [Any] {
                if containsSensitiveDataInArray(arrayValue) {
                    return true
                }
            }
        }
        return false
    }
    
    /// Scrubs sensitive patterns from a string.
    ///
    /// - Parameter string: The string to scrub
    /// - Returns: The scrubbed string with sensitive data redacted
    private static func scrubString(_ string: String) -> String {
        var scrubbed = string
        
        // Scrub nsec (private keys) - most critical
        scrubbed = scrubbed.replacingOccurrences(
            of: "nsec1[a-zA-Z0-9]{58,}",
            with: "[REDACTED_NSEC]",
            options: .regularExpression
        )
        
        // Scrub npub (public keys)
        scrubbed = scrubbed.replacingOccurrences(
            of: "npub1[a-zA-Z0-9]{58,}",
            with: "[REDACTED_NPUB]",
            options: .regularExpression
        )
        
        // Scrub note IDs
        scrubbed = scrubbed.replacingOccurrences(
            of: "note1[a-zA-Z0-9]{58,}",
            with: "[REDACTED_NOTE]",
            options: .regularExpression
        )
        
        // Scrub nevent (note events with relay hints)
        scrubbed = scrubbed.replacingOccurrences(
            of: "nevent1[a-zA-Z0-9]{58,}",
            with: "[REDACTED_NEVENT]",
            options: .regularExpression
        )
        
        // Scrub nprofile (profiles with relay hints)
        scrubbed = scrubbed.replacingOccurrences(
            of: "nprofile1[a-zA-Z0-9]{58,}",
            with: "[REDACTED_NPROFILE]",
            options: .regularExpression
        )
        
        // Scrub naddr (addressable/replaceable events)
        scrubbed = scrubbed.replacingOccurrences(
            of: "naddr1[a-zA-Z0-9]{58,}",
            with: "[REDACTED_NADDR]",
            options: .regularExpression
        )
        
        // Scrub nrelay (relay references)
        scrubbed = scrubbed.replacingOccurrences(
            of: "nrelay1[a-zA-Z0-9]+",
            with: "[REDACTED_NRELAY]",
            options: .regularExpression
        )
        
        // Scrub hex keys (64-character hex strings that might be keys)
        // Use word boundaries to avoid matching legitimate hex in other contexts
        scrubbed = scrubbed.replacingOccurrences(
            of: "\\b[0-9a-fA-F]{64}\\b",
            with: "[REDACTED_HEX]",
            options: .regularExpression
        )
        
        // Scrub email addresses
        scrubbed = scrubEmail(scrubbed)
        
        return scrubbed
    }
    
    /// Scrubs email addresses from a string.
    ///
    /// - Parameter string: The string to scrub
    /// - Returns: The string with email addresses redacted
    private static func scrubEmail(_ string: String) -> String {
        return string.replacingOccurrences(
            of: "[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}",
            with: "[REDACTED_EMAIL]",
            options: .regularExpression
        )
    }
    
    /// Scrubs sensitive data from a dictionary recursively.
    ///
    /// - Parameter dictionary: The dictionary to scrub (modified in place)
    private static func scrubDictionary(_ dictionary: inout [String: Any]) {
        for (key, value) in dictionary {
            if let stringValue = value as? String {
                dictionary[key] = scrubString(stringValue)
            } else if var nestedDict = value as? [String: Any] {
                scrubDictionary(&nestedDict)
                dictionary[key] = nestedDict
            } else if let array = value as? [Any] {
                dictionary[key] = scrubArray(array)
            }
        }
    }
    
    /// Scrubs sensitive data from an array recursively.
    ///
    /// - Parameter array: The array to scrub
    /// - Returns: A new array with scrubbed values
    private static func scrubArray(_ array: [Any]) -> [Any] {
        return array.map { item in
            if let stringValue = item as? String {
                return scrubString(stringValue)
            } else if var dictValue = item as? [String: Any] {
                scrubDictionary(&dictValue)
                return dictValue
            } else if let arrayValue = item as? [Any] {
                return scrubArray(arrayValue)
            }
            return item
        }
    }
    
    /// Scrubs sensitive data from a stacktrace.
    ///
    /// - Parameter stacktrace: The stacktrace to scrub (modified in place)
    private static func scrubStacktrace(_ stacktrace: SentryStacktrace) {
        let frames = stacktrace.frames
        for frame in frames {
            // Scrub function names
            if let function = frame.function {
                frame.function = scrubString(function)
            }
            // Scrub file paths (might contain sensitive info in URLs)
            if let fileName = frame.fileName {
                frame.fileName = scrubString(fileName)
            }
            // Scrub local variables
            if var vars = frame.vars {
                scrubDictionary(&vars)
                frame.vars = vars
            }
        }
    }
}
