///
//  ProfileBootstrap.swift
//  damus
//
//  Profile pre-cache bootstrap for new users
//

import Foundation

/// Loads bundled profile events on first launch
struct ProfileBootstrap {
    /// Check if bootstrap has already been loaded
    static var hasLoadedBootstrap: Bool {
        get {
            UserDefaults.standard.bool(forKey: "profile_bootstrap_loaded")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "profile_bootstrap_loaded")
        }
    }

    /// Load profile bootstrap data from bundle
    /// - Parameter ndb: NostrDB instance to process events into
    /// - Returns: Number of events loaded, or nil if bootstrap file not found
    static func loadIfNeeded(ndb: Ndb) -> Int? {
        // Skip if already loaded
        guard !hasLoadedBootstrap else {
            print("ProfileBootstrap: Already loaded, skipping")
            return nil
        }

        return load(ndb: ndb)
    }

    /// Force load bootstrap (ignores hasLoadedBootstrap flag)
    static func load(ndb: Ndb) -> Int? {
        print("ProfileBootstrap: Loading bundled profile data...")

        // Find bundle resource
        guard let bundleURL = Bundle.main.url(forResource: "profile-bootstrap", withExtension: "jsonl"),
              let jsonlData = try? Data(contentsOf: bundleURL),
              let jsonlString = String(data: jsonlData, encoding: .utf8) else {
            print("ProfileBootstrap: profile-bootstrap.jsonl not found in bundle")
            return nil
        }

        let lines = jsonlString.components(separatedBy: .newlines)
        var processedCount = 0
        var kind0Count = 0
        var kind3Count = 0

        for line in lines where !line.isEmpty {
            // Parse JSON event
            if let note = NdbNote.owned_from_json(json: line) {
                // Process into nostrdb
                _ = ndb.process_event(line)
                processedCount += 1

                // Track event kinds
                if note.known_kind == .metadata {
                    kind0Count += 1
                } else if note.known_kind == .contacts {
                    kind3Count += 1
                }
            }
        }

        print("ProfileBootstrap: Loaded \(processedCount) events")
        print("  - \(kind3Count) contact lists (kind 3)")
        print("  - \(kind0Count) profiles (kind 0)")

        // Mark as loaded
        hasLoadedBootstrap = true

        return processedCount
    }

    /// Reset bootstrap state (for testing)
    static func reset() {
        hasLoadedBootstrap = false
    }
}
