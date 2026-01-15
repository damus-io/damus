//
//  TorSessionFactory.swift
//  damus
//
//  Created for Tor mode support.
//

import Foundation

/// Factory for creating URLSessions configured to route through Tor via SOCKS5 proxy.
enum TorSessionFactory {
    #if !EXTENSION
    /// Lock for thread-safe access to cached state
    private static let lock = NSLock()

    /// Whether to use the embedded Arti client (true) or external SOCKS proxy (false).
    /// When true, the ArtiClient is started automatically if needed.
    static var useEmbeddedArti: Bool = true

    /// Cached session to avoid creating new ones repeatedly
    private static var cachedSession: URLSession?
    private static var cachedSessionPort: Int = 0
    private static var cachedSessionHost: String = ""
    private static var hasLoggedSessionCreation: Bool = false
    #endif

    /// Creates a URLSession configured to use a SOCKS5 proxy.
    ///
    /// - Parameters:
    ///   - host: The SOCKS5 proxy host (e.g., "127.0.0.1").
    ///   - port: The SOCKS5 proxy port (e.g., 9050 for Tor daemon, 9150 for Tor Browser).
    /// - Returns: A URLSession configured to route traffic through the specified SOCKS5 proxy.
    static func createSession(host: String, port: Int) -> URLSession {
        #if !EXTENSION
        // If using embedded Arti, start it and use its port
        if useEmbeddedArti {
            return getOrCreateArtiSession(fallbackHost: host, fallbackPort: port)
        }
        #endif

        return createSOCKSSession(host: host, port: port)
    }

    #if !EXTENSION
    /// Gets existing session or creates a new one using the embedded Arti client.
    /// Falls back to external proxy if Arti fails to start.
    private static func getOrCreateArtiSession(fallbackHost: String, fallbackPort: Int) -> URLSession {
        lock.lock()
        defer { lock.unlock() }

        let arti = ArtiClient.shared
        let artiReady = arti.socksPort > 0
        let targetHost = artiReady ? "127.0.0.1" : fallbackHost
        let targetPort = artiReady ? arti.socksPort : fallbackPort

        // Return cached session if host and port match
        if let session = cachedSession, cachedSessionPort == targetPort, cachedSessionHost == targetHost {
            return session
        }

        // Start Arti if stopped (not if already starting or running)
        if arti.state == .stopped {
            Log.info("[TOR] Starting embedded Arti client...", for: .networking)
            let result = arti.start(port: fallbackPort)

            switch result {
            case .success(let port):
                Log.info("[TOR] Arti starting on port %d", for: .networking, port)
            case .failure(let error):
                Log.error("[TOR] Failed to start Arti: %@, falling back to external proxy",
                         for: .networking, error.localizedDescription)
                let session = createSOCKSSession(host: fallbackHost, port: fallbackPort)
                cachedSession = session
                cachedSessionHost = fallbackHost
                cachedSessionPort = fallbackPort
                return session
            }
        }

        // Create and cache session
        let host = artiReady ? "127.0.0.1" : fallbackHost
        let port = artiReady ? arti.socksPort : fallbackPort

        if !hasLoggedSessionCreation {
            if artiReady {
                Log.info("[TOR] Using Arti SOCKS proxy on %@:%d", for: .networking, host, port)
            } else {
                Log.info("[TOR] Arti bootstrapping, using fallback proxy %@:%d", for: .networking, host, port)
            }
            hasLoggedSessionCreation = true
        }

        let session = createSOCKSSession(host: host, port: port, logCreation: false)
        cachedSession = session
        cachedSessionHost = host
        cachedSessionPort = port
        return session
    }
    #endif

    /// Creates a URLSession with SOCKS5 proxy configuration.
    private static func createSOCKSSession(host: String, port: Int, logCreation: Bool = true) -> URLSession {
        if logCreation {
            Log.info("[TOR] Creating SOCKS5 session via %@:%d", for: .networking, host, port)
        }

        let config = URLSessionConfiguration.default

        config.connectionProxyDictionary = [
            kCFProxyTypeKey: kCFProxyTypeSOCKS,
            kCFStreamPropertySOCKSProxyHost: host,
            kCFStreamPropertySOCKSProxyPort: port
        ]

        // Disable caching for privacy
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData

        return URLSession(configuration: config)
    }

    #if !EXTENSION
    /// Stops the embedded Arti client if running.
    static func stopArti() {
        lock.lock()
        defer { lock.unlock() }

        if ArtiClient.shared.isRunning {
            Log.info("[TOR] Stopping embedded Arti client", for: .networking)
            ArtiClient.shared.stop()
        }
        cachedSession = nil
        cachedSessionHost = ""
        cachedSessionPort = 0
        hasLoggedSessionCreation = false
    }
    #endif
}
