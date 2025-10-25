//
//  RelayPool+Testing.swift
//  damusTests
//
//  Created by OpenAI Codex on 2025-09-06.
//

import Foundation
@testable import damus

extension RelayPool {
    /// Marks the pool as open without creating real network connections, simplifying unit tests.
    func markOpenForTesting() async {
        self.open = true
    }
}
