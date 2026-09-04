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
        // `get_space_budget` adopts and writes a default when none is set, so a
        // leftover value from another test would decide these ones.
        UserDefaults.standard.removeObject(forKey: Ndb.space_budget_key)
    }

    override func tearDownWithError() throws {
        for dir in [sourceDir, outputDir] where !dir.isEmpty {
            try? FileManager.default.removeItem(atPath: dir)
        }
        UserDefaults.standard.removeObject(forKey: Ndb.space_budget_key)
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
            guard case NdbPruneError.pruneFailed(let path, let failure) = error else {
                return XCTFail("expected NdbPruneError.pruneFailed, got \(error)")
            }

            XCTAssertEqual(path, missing)

            // The whole point of the diagnostics: a failed prune has to say
            // *where* it failed and what LMDB said, because in the field the
            // stderr this used to be the only record of is long gone by the
            // time anyone reads the report. A missing directory is the one
            // failure we can provoke deterministically, and it goes through
            // exactly the same reporting path as the ones we cannot.
            XCTAssertEqual(failure.phase, "dst_env_open",
                           "a missing destination directory fails at mdb_env_open")
            XCTAssertEqual(failure.rc, Int32(ENOENT),
                           "and LMDB passes ENOENT straight through")
            XCTAssertNotNil(failure.rcDescription, "an rc we have must come with LMDB's text for it")
            XCTAssertEqual(failure.profilesCopied, 0)
            XCTAssertEqual(failure.notesCopied, 0)

            // Sentry is what actually reads this, and it only takes flat
            // strings — so the report has to be assembled here rather than in
            // the app target, which is where the error type cannot reach.
            let context = (error as! NdbPruneError).reportContext
            XCTAssertEqual(context["phase"], "dst_env_open")
            XCTAssertEqual(context["rc"], String(ENOENT))
            XCTAssertEqual(context["path"], missing)
            XCTAssertNotNil(context["destination_mapsize_bytes"],
                            "the destination mapsize is the one input to the open that nothing on our side picks")
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

    func test_the_default_capacity_is_exactly_what_the_keep_policy_needs() throws {
        // The keep-policy is the whole policy — nothing appends a `since` cutoff
        // or anything else to it any more — so a spare slot would be an
        // allocation with no caller.
        let filters = try NdbFilterArray.defaultPruneFilters(keeping: [alice.pubkey])
        XCTAssertEqual(filters.capacity, NdbFilterArray.defaultPruneFilterCapacity)
        XCTAssertEqual(filters.capacity, Int(NDB_PRUNE_DEFAULT_FILTERS))
        XCTAssertEqual(filters.count, filters.capacity)
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

    func test_a_built_filter_that_fails_halfway_leaves_the_count_alone() throws {
        let filters = NdbFilterArray(capacity: 2)

        // Two values in a single-valued field: nostrdb takes the first and rejects
        // the second, so this fails with a field already open.
        XCTAssertThrowsError(try filters.appendFilter(building: { filter in
            try filter.field(.since, { field in
                try field.add(int: 1)
                try field.add(int: 2)
            })
        })) { error in
            guard case NdbFilterBuildError.elementRejected = error else {
                return XCTFail("expected NdbFilterBuildError.elementRejected, got \(error)")
            }
        }
        XCTAssertEqual(filters.count, 0, "the half-built filter destroyed itself, so the slot is free again")

        // And the array is still usable: the freed slot takes the next filter.
        try filters.appendFilter(building: { filter in
            try filter.field(.since, { try $0.add(int: 1) })
        })
        XCTAssertEqual(filters.count, 1)
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

    func test_the_default_filters_keep_our_own_notes_of_every_kind() throws {
        // The load-bearing claim behind pruning with the defaults alone: the
        // author filter carries no kind restriction, so our contact list,
        // mutelist, relay list and bookmarks need no filter of their own. If nostrdb ever
        // narrowed that filter to kind 1 this test is what would say so.
        let ndb = try seeded(with: [
            try note("alice contacts", alice, kind: 3, at: 1700000000),
            try note("alice mutelist", alice, kind: 10000, at: 1700000001),
            try note("alice relays", alice, kind: 10002, at: 1700000002),
            try note("bob contacts", bob, kind: 3, at: 1700000003),
        ])
        defer { ndb.close() }

        try ndb.prune(to: outputDir, filters: try NdbFilterArray.defaultPruneFilters(keeping: [alice.pubkey]))

        XCTAssertEqual(try contents(inDatabaseAt: outputDir, kind: .contacts), ["alice contacts"],
                       "our own contact list survives, and it is not kept for someone else")
        XCTAssertEqual(try contents(inDatabaseAt: outputDir, kind: .mute_list), ["alice mutelist"])
        XCTAssertEqual(try contents(inDatabaseAt: outputDir, kind: .relay_list), ["alice relays"])
    }

    func test_the_default_filters_drop_everyone_elses_notes_however_new() throws {
        // The prune is all-or-nothing on purpose: no cutoff, so recency buys a
        // note nothing. Everything dropped here comes back from relays.
        let ndb = try seeded(with: [
            try note("bob ancient", bob, at: 1000000000),
            try note("bob a second ago", bob, at: 1900000000),
        ])
        defer { ndb.close() }

        try ndb.prune(to: outputDir, filters: try NdbFilterArray.defaultPruneFilters(keeping: [alice.pubkey]))

        XCTAssertEqual(try contents(inDatabaseAt: outputDir, kind: .text), [],
                       "nothing but profiles and our own notes survives, whatever its timestamp")
    }

    // MARK: - NdbSpaceBudget

    /// Gives `dir` a `data.mdb` of exactly `bytes`, without writing that many
    /// bytes: truncating an empty file leaves a sparse one whose reported size
    /// is the logical size, which is all `database_file_size` reads.
    private func makeDatabaseFile(inDirectory dir: String, ofSize bytes: UInt64) throws {
        let path = "\(dir)/\(Ndb.main_db_file_name)"
        if !FileManager.default.fileExists(atPath: path) {
            XCTAssertTrue(FileManager.default.createFile(atPath: path, contents: nil),
                          "could not create a stand-in database file at \(path)")
        }
        let handle = try XCTUnwrap(FileHandle(forWritingAtPath: path))
        defer { try? handle.close() }
        try handle.truncate(atOffset: bytes)
    }

    func test_space_budget_byte_values_are_the_ones_we_agreed() {
        XCTAssertEqual(NdbSpaceBudget.small.bytes, 512 * 1024 * 1024)
        XCTAssertEqual(NdbSpaceBudget.medium.bytes, 2 * 1024 * 1024 * 1024)
        XCTAssertEqual(NdbSpaceBudget.large.bytes, 8 * 1024 * 1024 * 1024)
        XCTAssertNil(NdbSpaceBudget.unlimited.bytes, "unlimited is the opt-out, so it has no cap at all")
    }

    func test_space_budget_cases_are_ordered_smallest_first() {
        // Load-bearing twice over: the settings picker lists them in this order,
        // and `default_space_budget` takes the first tier that fits.
        XCTAssertEqual(NdbSpaceBudget.allCases, [.small, .medium, .large, .unlimited])
        let capped = NdbSpaceBudget.allCases.compactMap(\.bytes)
        XCTAssertEqual(capped, capped.sorted())
    }

    func test_space_budget_round_trips_through_user_defaults() {
        for budget in NdbSpaceBudget.allCases {
            Ndb.set_space_budget(budget)
            XCTAssertEqual(Ndb.get_space_budget(db_path: sourceDir), budget)
        }
    }

    func test_default_space_budget_is_the_tightest_tier_the_database_already_fits() {
        let mb = UInt64(1024 * 1024)
        let gb = 1024 * mb

        XCTAssertEqual(Ndb.default_space_budget(forDatabaseSizeBytes: 0), .small)
        XCTAssertEqual(Ndb.default_space_budget(forDatabaseSizeBytes: 512 * mb), .small,
                       "a database exactly at a tier still fits inside it")
        XCTAssertEqual(Ndb.default_space_budget(forDatabaseSizeBytes: 512 * mb + 1), .medium)
        XCTAssertEqual(Ndb.default_space_budget(forDatabaseSizeBytes: 2 * gb), .medium)
        XCTAssertEqual(Ndb.default_space_budget(forDatabaseSizeBytes: 2 * gb + 1), .large)
        XCTAssertEqual(Ndb.default_space_budget(forDatabaseSizeBytes: 8 * gb), .large)
        XCTAssertEqual(Ndb.default_space_budget(forDatabaseSizeBytes: 8 * gb + 1), .unlimited,
                       "a database bigger than every tier opts out rather than being pruned the moment its owner updates")
    }

    func test_a_fresh_install_with_no_database_starts_at_the_smallest_tier() {
        XCTAssertEqual(Ndb.get_space_budget(db_path: sourceDir), .small)
    }

    func test_the_first_read_adopts_a_tier_from_the_database_size_and_then_sticks_to_it() throws {
        try makeDatabaseFile(inDirectory: sourceDir, ofSize: 3 * 1024 * 1024 * 1024)

        XCTAssertEqual(Ndb.get_space_budget(db_path: sourceDir), .large,
                       "an existing 3 GB install starts on the tier it already fits, not the smallest one")
        XCTAssertEqual(UserDefaults.standard.string(forKey: Ndb.space_budget_key),
                       NdbSpaceBudget.large.rawValue,
                       "the adopted default has to be written back, or it would be re-derived on every read")

        // Growing past the adopted tier must not move the tier: a budget that
        // drifted upwards with the database would never trigger a prune.
        try makeDatabaseFile(inDirectory: sourceDir, ofSize: 9 * 1024 * 1024 * 1024)
        XCTAssertEqual(Ndb.get_space_budget(db_path: sourceDir), .large)
    }
}
