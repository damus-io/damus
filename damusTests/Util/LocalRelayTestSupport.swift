//
//  LocalRelayTestSupport.swift
//  damusTests
//
//  Created by Claude on 2026-09-08.
//

import Foundation
import NostrSDK

/// Starts throwaway `LocalRelay` instances for tests without pinning a port.
///
/// Tests used to hand `RelayBuilder.port(port:)` a hardcoded number, which made any two
/// concurrent runs on the same host fight over the same socket: Xcode Cloud runs `damusTests`
/// against four simulator destinations at once and simulators share the host's loopback, so the
/// loser died with `Address already in use (os error 48)`. Two worktrees testing at once collide
/// the same way. Leaving the port unset lets the relay pick a free one itself, and every caller
/// already derives its relay URL from ``LocalRelay/url()``, so tests talk to the port the relay
/// actually bound rather than the number we asked for.
enum LocalRelayTestSupport {
    /// How many times to start the relay before giving up.
    ///
    /// The relay picks its port by probing one and then binding it, so a concurrent run can still
    /// take the port in between. Each retry builds a fresh relay, which re-rolls the port.
    private static let startAttempts = 5

    enum StartError: Error {
        /// Every attempt to bind a port failed, carrying the last failure.
        case couldNotStart(attempts: Int, lastError: Error?)
    }

    /// Creates and runs a local relay on a free port of the OS's choosing.
    /// - Parameter configure: Applies any extra builder options, e.g. a rate limit.
    /// - Returns: The running `LocalRelay`. Callers must keep hold of it — the relay shuts down
    ///   as soon as the last reference to it is released.
    static func startRelay(
        configure: (RelayBuilder) -> RelayBuilder = { $0 }
    ) async throws -> LocalRelay {
        var lastError: Error?
        for _ in 0..<startAttempts {
            // A fresh builder and relay per attempt, so a retry gets a fresh port
            let relay = LocalRelay(builder: configure(RelayBuilder()))
            do {
                try await relay.run()
                print("Relay url: \(await relay.url())")
                return relay
            }
            catch {
                lastError = error
                print("Could not start local relay, retrying on another port: \(error)")
            }
        }
        throw StartError.couldNotStart(attempts: startAttempts, lastError: lastError)
    }
}
