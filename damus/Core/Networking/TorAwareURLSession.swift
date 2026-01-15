//
//  TorAwareURLSession.swift
//  damus
//
//  Provides a centralized URLSession that routes through Tor when enabled.
//

import Foundation

/// Provides URLSession instances that automatically route through Tor when Tor mode is enabled.
/// Use this instead of URLSession.shared throughout the app to ensure all traffic respects Tor settings.
enum TorAwareURLSession {
    /// Returns a URLSession configured for the current Tor setting.
    /// - When Tor is enabled: Returns a SOCKS5-configured session routing through Tor
    /// - When Tor is disabled: Returns URLSession.shared
    ///
    /// Note: This reads the setting each time, so it reflects the current state.
    /// For long-lived sessions, consider caching and refreshing on app lifecycle events.
    static var shared: URLSession {
        guard isTorEnabled else {
            return URLSession.shared
        }

        #if !EXTENSION
        // In main app, use TorSessionFactory which manages Arti
        let settings = UserSettingsStore.shared ?? UserSettingsStore()
        return TorSessionFactory.createSession(
            host: settings.tor_socks_host,
            port: settings.tor_socks_port
        )
        #else
        // In extensions, create SOCKS session directly (Arti not available)
        return createSOCKSSession()
        #endif
    }

    /// Creates a SOCKS5-configured URLSession directly.
    /// Used by extensions where Arti/TorSessionFactory is not available.
    private static func createSOCKSSession() -> URLSession {
        let settings = UserSettingsStore.shared ?? UserSettingsStore()
        let config = URLSessionConfiguration.default
        config.connectionProxyDictionary = [
            kCFProxyTypeKey: kCFProxyTypeSOCKS,
            kCFStreamPropertySOCKSProxyHost: settings.tor_socks_host,
            kCFStreamPropertySOCKSProxyPort: settings.tor_socks_port
        ]
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 300
        return URLSession(configuration: config)
    }

    /// Returns the appropriate SOCKS host and port based on Arti status.
    /// Uses Arti's port when running, otherwise falls back to user settings.
    private static func getSOCKSHostAndPort() -> (host: String, port: Int) {
        let settings = UserSettingsStore.shared ?? UserSettingsStore()

        #if !EXTENSION
        // Use Arti's port when it's running, otherwise use configured settings
        if ArtiClient.shared.socksPort > 0 {
            return ("127.0.0.1", ArtiClient.shared.socksPort)
        }
        #endif

        return (settings.tor_socks_host, settings.tor_socks_port)
    }

    /// Returns a URLSession with custom configuration that routes through Tor when enabled.
    /// - Parameter configuration: Base configuration to apply Tor proxy settings to
    /// - Returns: Configured URLSession
    static func session(with configuration: URLSessionConfiguration) -> URLSession {
        guard isTorEnabled else {
            return URLSession(configuration: configuration)
        }

        let (host, port) = getSOCKSHostAndPort()

        configuration.connectionProxyDictionary = [
            kCFProxyTypeKey: kCFProxyTypeSOCKS,
            kCFStreamPropertySOCKSProxyHost: host,
            kCFStreamPropertySOCKSProxyPort: port
        ]

        // Disable caching for privacy when using Tor
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData

        // Increase timeouts for Tor (it's slower)
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 300

        return URLSession(configuration: configuration)
    }

    /// Returns a URLSession suitable for image/media loading with appropriate timeouts.
    /// Configures longer timeouts when Tor is enabled to account for slower speeds.
    static var mediaSession: URLSession {
        let config = URLSessionConfiguration.default

        guard isTorEnabled else {
            // Standard timeouts for direct connections
            config.timeoutIntervalForRequest = 30
            config.timeoutIntervalForResource = 120
            return URLSession(configuration: config)
        }

        let (host, port) = getSOCKSHostAndPort()

        config.connectionProxyDictionary = [
            kCFProxyTypeKey: kCFProxyTypeSOCKS,
            kCFStreamPropertySOCKSProxyHost: host,
            kCFStreamPropertySOCKSProxyPort: port
        ]

        // Longer timeouts for media over Tor
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 600

        // Disable caching for privacy
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData

        return URLSession(configuration: config)
    }

    /// Whether Tor mode is currently enabled
    static var isTorEnabled: Bool {
        (UserSettingsStore.shared ?? UserSettingsStore()).tor_enabled
    }
}
