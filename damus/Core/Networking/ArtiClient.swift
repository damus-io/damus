//
//  ArtiClient.swift
//  damus
//
//  Swift wrapper for Arti Tor client.
//

import Foundation

/// Manages the embedded Arti Tor client.
/// Provides a SOCKS5 proxy on localhost for routing traffic through Tor.
final class ArtiClient: ObservableObject {
    /// Shared instance
    static let shared = ArtiClient()

    /// Current state of the Arti client
    @Published private(set) var state: ArtiState = .stopped

    /// Current SOCKS port (0 if not running)
    @Published private(set) var socksPort: Int = 0

    /// Whether Arti is currently running
    var isRunning: Bool { state == .running }

    /// Default SOCKS port
    static let defaultPort: Int = 9050

    /// Lock for thread-safe state transitions
    private let stateLock = NSLock()

    /// Internal state for lock-protected access (avoids @Published deadlock)
    private var internalState: ArtiState = .stopped

    /// Arti state directory
    private var stateDir: URL {
        let baseDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return baseDir.appendingPathComponent("arti/state", isDirectory: true)
    }

    /// Arti cache directory
    private var cacheDir: URL {
        let baseDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return baseDir.appendingPathComponent("arti/cache", isDirectory: true)
    }

    private init() {}

    /// Starts the Arti SOCKS proxy on a background thread.
    ///
    /// The startup is asynchronous - this method returns immediately with the expected port.
    /// Monitor the `state` property to know when Arti is fully running.
    ///
    /// - Parameter port: SOCKS proxy port (default: 9050)
    /// - Returns: Result with the expected port, or error if startup cannot begin
    @discardableResult
    func start(port: Int = defaultPort) -> Result<Int, ArtiError> {
        // Check and update state atomically
        let canStart: Bool
        stateLock.lock()
        switch internalState {
        case .stopped:
            internalState = .starting
            canStart = true
        case .running:
            stateLock.unlock()
            return .success(socksPort)
        case .starting:
            stateLock.unlock()
            return .success(port)
        case .stopping:
            stateLock.unlock()
            return .failure(.invalidState("Cannot start while stopping"))
        }
        stateLock.unlock()

        guard canStart else { return .failure(.invalidState("Unexpected state")) }

        // Update published state on main thread (no lock held)
        DispatchQueue.main.async { [weak self] in
            self?.state = .starting
        }

        // Capture paths before async
        let statePath = stateDir.path
        let cachePath = cacheDir.path

        // All heavy work on background thread
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            // Create directories on background thread
            do {
                try FileManager.default.createDirectory(atPath: statePath, withIntermediateDirectories: true)
                try FileManager.default.createDirectory(atPath: cachePath, withIntermediateDirectories: true)
            } catch {
                Log.error("[TOR] Failed to create directories: %@", for: .networking, error.localizedDescription)
                self?.transitionState(to: .stopped)
                return
            }

            let result = arti_start(statePath, cachePath, Int32(port)) { logMessage in
                guard let msg = logMessage else { return }
                Log.info("[ARTI] %@", for: .networking, String(cString: msg))
            }

            guard let resultPtr = result else {
                self?.transitionState(to: .stopped)
                return
            }

            let resultStr = String(cString: resultPtr)
            arti_free_string(resultPtr)

            if resultStr.hasPrefix("Error:") {
                Log.error("[TOR] Arti start failed: %@", for: .networking, resultStr)
                self?.transitionState(to: .stopped)
                return
            }

            // Poll for running state
            self?.pollForRunningState(expectedPort: port)
        }

        return .success(port)
    }

    /// Polls until Arti reports running state or timeout.
    private func pollForRunningState(expectedPort: Int, timeoutSeconds: Int = 30) {
        let iterations = timeoutSeconds * 10
        for _ in 0..<iterations {
            Thread.sleep(forTimeInterval: 0.1)

            // Check if stop was requested during startup
            stateLock.lock()
            let currentState = internalState
            stateLock.unlock()
            if currentState == .stopping || currentState == .stopped {
                return
            }

            guard arti_is_running() == 1 else { continue }

            let actualPort = Int(arti_get_socks_port())
            transitionState(to: .running, port: actualPort)
            return
        }
        transitionState(to: .stopped)
    }

    /// Atomically transitions state and updates published properties.
    private func transitionState(to newState: ArtiState, port: Int? = nil) {
        stateLock.lock()
        internalState = newState
        stateLock.unlock()

        DispatchQueue.main.async { [weak self] in
            self?.state = newState
            if let port = port {
                self?.socksPort = port
            } else if newState == .stopped {
                self?.socksPort = 0
            }
        }
    }

    /// Stops the Arti proxy asynchronously.
    /// Can be called during .starting or .running states.
    func stop() {
        stateLock.lock()
        guard internalState == .running || internalState == .starting else {
            stateLock.unlock()
            return
        }
        internalState = .stopping
        stateLock.unlock()

        // Update published state (no lock held)
        DispatchQueue.main.async { [weak self] in
            self?.state = .stopping
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            arti_stop()

            // Poll for stopped state (10 second timeout)
            for _ in 0..<100 {
                Thread.sleep(forTimeInterval: 0.1)
                if arti_is_running() == 0 { break }
            }
            self?.transitionState(to: .stopped)
        }
    }

    /// Create a URLSession configured to use the Arti SOCKS proxy.
    /// - Returns: URLSession configured for Tor, or nil if Arti is not running
    func createURLSession() -> URLSession? {
        guard isRunning, socksPort > 0 else { return nil }
        return TorSessionFactory.createSession(host: "127.0.0.1", port: socksPort)
    }
}

// MARK: - Types

extension ArtiClient {
    /// Arti client state
    enum ArtiState: String, CustomStringConvertible {
        case stopped = "Stopped"
        case starting = "Starting"
        case running = "Running"
        case stopping = "Stopping"

        var description: String { rawValue }
    }

    /// Arti errors
    enum ArtiError: Error, LocalizedError {
        case invalidState(String)
        case directoryCreationFailed(String)
        case startFailed(String)

        var errorDescription: String? {
            switch self {
            case .invalidState(let msg): return "Invalid state: \(msg)"
            case .directoryCreationFailed(let msg): return "Failed to create directory: \(msg)"
            case .startFailed(let msg): return "Failed to start Arti: \(msg)"
            }
        }
    }
}
