//
//  NdbPruneTests.swift
//  damusTests
//
//  Covers the Phase 1 bindings for `ndb_prune` and `ndb_prune_default_filters`:
//  that a prune really drops the notes no filter matches, and that the filters
//  handed back by nostrdb are owned and freed by `NdbFilterArray`.
//

import XCTest
@testable import damus

final class NdbPruneTests: XCTestCase {
    /// Where the seeded source database lives.
    var sourceDir: String = ""
    /// Where prunes are written. Created empty for each test, since LMDB will
    /// not create the destination directory itself.
    var outputDir: String = ""

    let alice = generate_new_keypair()
    let bob = generate_new_keypair()

    override func setUpWithError() throws {
        sourceDir = try XCTUnwrap(test_ndb_dir(), "could not create a source directory")
        outputDir = try XCTUnwrap(test_ndb_dir(), "could not create an output directory")
    }

    override func tearDownWithError() throws {
        for dir in [sourceDir, outputDir] where !dir.isEmpty {
            try? FileManager.default.removeItem(atPath: dir)
        }
    }

    // MARK: - Fixtures

    /// Wraps signed events into the wire format `process_events` reads. The
    /// trailing newline matters: `ndb_process_events` only ingests up to the last
    /// `\n`.
    private func wire(_ events: [NostrEvent]) -> String {
        return events.compactMap({ encode_json($0) }).map({ "[\"EVENT\",\"s\",\($0)]\n" }).joined()
    }

    private func note(_ content: String, _ keypair: FullKeypair, kind: UInt32 = 1, at timestamp: UInt32) throws -> NostrEvent {
        return try XCTUnwrap(NostrEvent(content: content,
                                        keypair: keypair.to_keypair(),
                                        kind: kind,
                                        tags: [],
                                        createdAt: timestamp))
    }

    private func profile(_ name: String, _ keypair: FullKeypair, at timestamp: UInt32) throws -> NostrEvent {
        return try note("{\"name\":\"\(name)\"}", keypair, kind: 0, at: timestamp)
    }

    /// Ingests `events` into `sourceDir` and hands back a freshly opened `Ndb`.
    ///
    /// Ingestion is asynchronous, so the seeding database is closed —
    /// `ndb_destroy` drains the writer — before the one under test is opened.
    private func seeded(with events: [NostrEvent]) throws -> Ndb {
        let seeder = try XCTUnwrap(Ndb(path: sourceDir))
        XCTAssertTrue(seeder.process_events(wire(events)))
        seeder.close()
        return try XCTUnwrap(Ndb(path: sourceDir))
    }

    /// The contents of every note of `kind` in the database at `path`, sorted so
    /// comparisons do not depend on the order the prune rewrote them in.
    private func contents(inDatabaseAt path: String, kind: NostrKind) throws -> [String] {
        let ndb = try XCTUnwrap(Ndb(path: path, owns_db_file: false))
        defer { ndb.close() }

        let filter = try NdbFilter(from: NostrFilter(kinds: [kind]))
        let keys = try ndb.query(filters: [filter], maxResults: 100)
        return try ndb.compact_map_notes(keys: keys, { _, note in note.content }).sorted()
    }

    // MARK: - prune(to:filters:)

    func test_prune_with_an_author_filter_keeps_only_that_authors_notes() throws {
        let ndb = try seeded(with: [
            try note("alice one", alice, at: 1700000000),
            try note("alice two", alice, at: 1700000001),
            try note("bob one", bob, at: 1700000002),
        ])
        defer { ndb.close() }

        let keepAlice = try NdbFilter(from: NostrFilter(authors: [alice.pubkey]))
        try ndb.prune(to: outputDir, filters: [keepAlice])

        XCTAssertEqual(try contents(inDatabaseAt: outputDir, kind: .text),
                       ["alice one", "alice two"],
                       "a prune filtered to alice should drop bob's note")
    }

    func test_prune_with_no_filters_keeps_everything() throws {
        let ndb = try seeded(with: [
            try note("alice one", alice, at: 1700000000),
            try note("bob one", bob, at: 1700000001),
        ])
        defer { ndb.close() }

        // Filters are unioned, and nostrdb treats "no filters" as "match
        // everything" — so this is a copy, not an empty database.
        try ndb.prune(to: outputDir, filters: [NdbFilter]())

        XCTAssertEqual(try contents(inDatabaseAt: outputDir, kind: .text),
                       ["alice one", "bob one"],
                       "an empty filter array should keep every note")
    }

    func test_prune_fails_when_the_output_directory_does_not_exist() throws {
        let ndb = try seeded(with: [try note("alice one", alice, at: 1700000000)])
        defer { ndb.close() }

        let missing = outputDir + "/does-not-exist"
        XCTAssertThrowsError(try ndb.prune(to: missing, filters: [NdbFilter]()),
                             "LMDB does not create the destination directory, so this must fail rather than silently succeed") { error in
            guard case NdbPruneError.pruneFailed = error else {
                return XCTFail("expected NdbPruneError.pruneFailed, got \(error)")
            }
        }
    }

    func test_prune_survives_a_filter_array_the_caller_does_not_otherwise_hold() throws {
        let ndb = try seeded(with: [
            try note("alice one", alice, at: 1700000000),
            try note("bob one", bob, at: 1700000001),
        ])
        defer { ndb.close() }

        // The NdbFilter is a temporary with no binding of its own, so nothing but
        // `prune`'s own lifetime handling keeps its heap allocation — which the
        // copied `ndb_filter` struct still points into — alive across the call.
        try ndb.prune(to: outputDir, filters: [try NdbFilter(from: NostrFilter(authors: [bob.pubkey]))])

        XCTAssertEqual(try contents(inDatabaseAt: outputDir, kind: .text), ["bob one"])
    }

    // MARK: - NdbFilterArray.defaultPruneFilters

    func test_default_prune_filters_emits_only_the_profile_filter_with_no_pubkeys() throws {
        // An authors field with no elements matches nothing, so nostrdb skips the
        // authors filter entirely rather than emitting an unsatisfiable one.
        let filters = try NdbFilterArray.defaultPruneFilters(keeping: [])
        XCTAssertEqual(filters.count, 1)
    }

    func test_default_prune_filters_emits_both_filters_with_a_pubkey() throws {
        let filters = try NdbFilterArray.defaultPruneFilters(keeping: [alice.pubkey])
        XCTAssertEqual(filters.count, Int(NDB_PRUNE_DEFAULT_FILTERS))
    }

    func test_default_prune_filters_rejects_a_capacity_below_the_minimum() throws {
        XCTAssertThrowsError(try NdbFilterArray.defaultPruneFilters(keeping: [alice.pubkey], capacity: 1)) { error in
            guard case NdbFilterArrayError.capacityTooSmall(let capacity, let minimum) = error else {
                return XCTFail("expected NdbFilterArrayError.capacityTooSmall, got \(error)")
            }
            XCTAssertEqual(capacity, 1)
            XCTAssertEqual(minimum, Int(NDB_PRUNE_DEFAULT_FILTERS))
        }
    }

    func test_default_prune_filters_leaves_a_spare_slot_for_one_appended_filter() throws {
        let filters = try NdbFilterArray.defaultPruneFilters(keeping: [alice.pubkey])
        XCTAssertEqual(filters.capacity, NdbFilterArray.defaultPruneFilterCapacity)
        XCTAssertEqual(filters.capacity - filters.count, 1,
                       "the default capacity should leave exactly one slot for a caller-appended filter")

        try filters.appendFilter({ slot in
            guard ndb_filter_init(slot) == 1 else { return false }
            guard ndb_filter_start_field(slot, NDB_FILTER_SINCE) == 1,
                  ndb_filter_add_int_element(slot, 1700000000) == 1 else {
                ndb_filter_destroy(slot)
                return false
            }
            ndb_filter_end_field(slot)
            guard ndb_filter_end(slot) == 1 else {
                ndb_filter_destroy(slot)
                return false
            }
            return true
        })

        XCTAssertEqual(filters.count, 3)
    }

    func test_append_filter_throws_once_the_array_is_full() throws {
        let filters = NdbFilterArray(capacity: 1)
        let initializeAnyFilter: (UnsafeMutablePointer<ndb_filter>) -> Bool = { slot in
            return ndb_filter_init(slot) == 1 && ndb_filter_end(slot) == 1
        }

        try filters.appendFilter(initializeAnyFilter)
        XCTAssertEqual(filters.count, 1)

        XCTAssertThrowsError(try filters.appendFilter(initializeAnyFilter)) { error in
            guard case NdbFilterArrayError.full(let capacity) = error else {
                return XCTFail("expected NdbFilterArrayError.full, got \(error)")
            }
            XCTAssertEqual(capacity, 1)
        }
        XCTAssertEqual(filters.count, 1, "a rejected append must not bump the count")
    }

    func test_append_filter_that_reports_failure_leaves_the_count_alone() throws {
        let filters = NdbFilterArray(capacity: 2)
        XCTAssertThrowsError(try filters.appendFilter({ _ in false })) { error in
            guard case NdbFilterArrayError.filterInitializationFailed = error else {
                return XCTFail("expected NdbFilterArrayError.filterInitializationFailed, got \(error)")
            }
        }
        XCTAssertEqual(filters.count, 0, "an uninitialized slot must not be counted, or deinit would destroy garbage")
    }

    // MARK: - The two together

    func test_prune_with_the_default_filters_keeps_profiles_and_our_own_notes() throws {
        let ndb = try seeded(with: [
            try profile("alice", alice, at: 1700000000),
            try profile("bob", bob, at: 1700000001),
            try note("alice one", alice, at: 1700000002),
            try note("bob one", bob, at: 1700000003),
            try note("bob two", bob, at: 1700000004),
        ])
        defer { ndb.close() }

        let filters = try NdbFilterArray.defaultPruneFilters(keeping: [alice.pubkey])
        try ndb.prune(to: outputDir, filters: filters)

        XCTAssertEqual(try contents(inDatabaseAt: outputDir, kind: .text),
                       ["alice one"],
                       "the default policy keeps our own notes and drops everyone else's")
        XCTAssertEqual(try contents(inDatabaseAt: outputDir, kind: .metadata).count, 2,
                       "the default policy keeps every kind-0 profile, ours or not")
    }
}
