//
//  NdbIngesterKeyTests.swift
//  damusTests
//

import XCTest
@testable import damus

/// Covers ``Ndb/add_key(_:)``, the registration that lets nostrdb's ingester threads
/// unwrap NIP-59 giftwraps addressed to us.
///
/// Not covered here: that a registered key actually turns inbound kind-1059s into
/// stored kind-14 rumors. That needs a real giftwrap fixture and belongs with the
/// giftwrap round-trip tests.
final class NdbIngesterKeyTests: XCTestCase {
    func testAddKeyReachesTheIngesterThreads() {
        let ndb = Ndb.test
        defer { ndb.close() }

        XCTAssertTrue(
            ndb.add_key(generate_new_keypair().privkey),
            "add_key should dispatch the key to the ingester threads of an open database"
        )
    }

    /// Registration goes through `withNdb` like the other wrappers, so it must refuse to
    /// touch a destroyed `ndb` — and must start working again once one is back.
    func testAddKeyFailsWhileClosedAndSucceedsAfterReopen() {
        let ndb = Ndb.test
        defer { ndb.close() }

        ndb.close()
        XCTAssertFalse(
            ndb.add_key(generate_new_keypair().privkey),
            "add_key must not dispatch into a destroyed ndb"
        )

        XCTAssertTrue(ndb.reopen(), "the test database should reopen")
        XCTAssertTrue(
            ndb.add_key(generate_new_keypair().privkey),
            "a reopened database has fresh ingester threads and should accept registrations again"
        )
    }
}
