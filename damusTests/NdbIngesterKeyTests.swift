//
//  NdbIngesterKeyTests.swift
//  damusTests
//

import XCTest
@testable import damus

/// Covers ``Ndb/add_key(_:)`` — the registration that lets nostrdb's ingester threads
/// unwrap NIP-59 giftwraps addressed to us — and ``Ndb/process_giftwraps()``, the
/// backfill that re-dispatches wraps stored before we had a key.
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

    // MARK: Giftwrap backfill

    /// The backfill walks the kind-1059 index, so a database that has never seen one
    /// has nothing to hand back.
    func testProcessGiftwrapsDispatchesNothingWithoutStoredWraps() throws {
        let ndb = try seeded(with: [try note(kind: 1, content: "not a giftwrap")])
        defer { ndb.close() }

        XCTAssertEqual(try ndb.process_giftwraps(), 0)
    }

    /// The point of the backfill: a wrap that was already sitting in the database gets
    /// re-dispatched to the ingester pool.
    ///
    /// The wrap here is signed but its content is not real NIP-44 ciphertext, so the
    /// unwrap attempt on the other side will fail. That is fine — this asserts on what
    /// the walk dispatches, not on what comes back out.
    func testProcessGiftwrapsDispatchesStoredWraps() throws {
        let ndb = try seeded(with: [
            try note(kind: 1059, content: "wrapped"),
            try note(kind: 1, content: "not a giftwrap"),
        ])
        defer { ndb.close() }

        XCTAssertEqual(try ndb.process_giftwraps(), 1)
    }

    /// The walk goes through `withNdb` like everything else, so a torn-down database
    /// must throw rather than run a cursor over freed memory.
    func testProcessGiftwrapsThrowsWhileClosed() throws {
        let ndb = try seeded(with: [try note(kind: 1059, content: "wrapped")])
        ndb.close()

        XCTAssertThrowsError(try ndb.process_giftwraps())
    }

    // MARK: Helpers

    private func note(kind: UInt32, content: String) throws -> NostrEvent {
        return try XCTUnwrap(NostrEvent(content: content,
                                        keypair: generate_new_keypair().to_keypair(),
                                        kind: kind,
                                        tags: []))
    }

    /// Ingests `events` and hands back a freshly opened `Ndb` reading the same files.
    ///
    /// Closing the first handle is what makes this deterministic: ingestion is async on
    /// the ingester pool, and `ndb_destroy` drains it. Reopening then reads a database
    /// the events are known to be in.
    private func seeded(with events: [NostrEvent]) throws -> Ndb {
        let dir = try XCTUnwrap(test_ndb_dir(), "could not create a temp directory")
        // `ndb_process_events` only ingests up to the last newline, so every line needs one.
        let wire = events.compactMap({ encode_json($0) }).map({ "[\"EVENT\",\"s\",\($0)]\n" }).joined()

        do {
            let seed = try XCTUnwrap(Ndb(path: dir))
            XCTAssertTrue(seed.process_events(wire))
            seed.close()
        }

        return try XCTUnwrap(Ndb(path: dir))
    }
}
