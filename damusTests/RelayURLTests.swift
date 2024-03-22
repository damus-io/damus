//
//  RelayURLTests.swift
//  damusTests
//
//  Created by Daniel D’Aquino on 2024-03-20.
//

import Foundation
import XCTest
@testable import damus

final class RelayURLTests : XCTestCase {
    func testRelayURLTrailingSlash() {
        let relay_url_1: RelayURL = RelayURL("wss://relay.damus.io")!
        let relay_url_2: RelayURL = RelayURL("wss://relay.damus.io/")!

        XCTAssertEqual(relay_url_1.id, relay_url_2.id, "Relays with the same address should have the same ID even if one of them was initialized with a trailing slash")
        XCTAssertEqual(relay_url_1, relay_url_2, "Relays with the same address should be equal even if one of them was initialized with a trailing slash")

        var relays: [RelayURL: Int] = [:]
        relays[relay_url_1] = 1
        relays[relay_url_2] = 2

        XCTAssertEqual(relays[relay_url_1], 2, "RelayURL with a trailing slash should evaluate to the same hash in a dictionary as an equivalent one without trailing slashes")
    }

    func testRelayURLDifferentProtocols() {
        let relay_url_1: RelayURL = RelayURL("wss://relay.damus.io")!
        let relay_url_2: RelayURL = RelayURL("ws://relay.damus.io")!

        XCTAssertNotEqual(relay_url_1.id, relay_url_2.id, "Relays with different protocols should not have the same ID")
        XCTAssertNotEqual(relay_url_1, relay_url_2, "Relays with different protocols should not be equal")

        var relays: [RelayURL: Int] = [:]
        relays[relay_url_1] = 1
        relays[relay_url_2] = 2

        XCTAssertNotEqual(relays[relay_url_1], relays[relay_url_2], "RelayURL with different protocols should not evaluate to the same hash in a dictionary")
    }

    func testRelayURLDifferentDomains() {
        let relay_url_1: RelayURL = RelayURL("wss://relay.damus.io")!
        let relay_url_3: RelayURL = RelayURL("wss://example.com")!

        XCTAssertNotEqual(relay_url_1, relay_url_3, "Relays with different domains should not be equal")

        var relays: [RelayURL: Int] = [:]
        relays[relay_url_1] = 1
        relays[relay_url_3] = 3

        XCTAssertNotEqual(relays[relay_url_1], relays[relay_url_3], "RelayURL with different domains should not evaluate to the same hash in a dictionary")
    }

    func testRelayURLDifferentPaths() {
        let relay_url_1: RelayURL = RelayURL("wss://relay.damus.io")!
        let relay_url_2: RelayURL = RelayURL("wss://relay.damus.io/")!
        let relay_url_3: RelayURL = RelayURL("wss://relay.damus.io/v1")!
        let relay_url_4: RelayURL = RelayURL("wss://relay.damus.io/v2")!
        let relay_url_5: RelayURL = RelayURL("wss://relay.damus.io/v2/beta")!
        let relay_url_6: RelayURL = RelayURL("wss://relay.damus.io/v2/beta/")!

        XCTAssertEqual(relay_url_1.id, relay_url_2.id, "Relays with the same address should have the same ID even if one of them was initialized with a trailing slash")
        XCTAssertEqual(relay_url_1, relay_url_2, "Relays with the same address should be equal even if one of them was initialized with a trailing slash")

        XCTAssertNotEqual(relay_url_1, relay_url_3, "Relays with different paths should not be equal")
        XCTAssertNotEqual(relay_url_3, relay_url_4, "Relays with different paths should not be equal")
        XCTAssertNotEqual(relay_url_4, relay_url_5, "Relays with different subpaths should not be equal")
        XCTAssertEqual(relay_url_5, relay_url_6, "Relays with the same address should be equal if one of them is initialized with a trailing slash")

        var relays: [RelayURL: Int] = [:]
        relays[relay_url_1] = 1
        relays[relay_url_2] = 2
        relays[relay_url_3] = 3
        relays[relay_url_4] = 4
        relays[relay_url_5] = 5
        relays[relay_url_6] = 6

        XCTAssertEqual(relays[relay_url_1], relays[relay_url_2], "RelayURL with the same path should evaluate to the same hash in a dictionary")
        XCTAssertNotEqual(relays[relay_url_1], relays[relay_url_3], "RelayURLs with different pathsshould not evaluate to the same hash in a dictionary")
        XCTAssertNotEqual(relays[relay_url_3], relays[relay_url_4], "RelayURLs with different paths should not evaluate to the same hash in a dictionary")
        XCTAssertNotEqual(relays[relay_url_4], relays[relay_url_5], "RelayURLs with different subpaths should not evaluate to the same hash in a dictionary")
        XCTAssertEqual(relays[relay_url_5], relays[relay_url_6], "RelayURL with the same subpath should evaluate to the same hash in a dictionary even if one of them is initialized with a trailing slash")
    }
}
