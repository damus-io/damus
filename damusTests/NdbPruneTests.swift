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

    // MARK: - NdbNoteSizeHistogram

    /// Three timestamps on three consecutive, distinct UTC days, newest first.
    private static let day = UInt32(NdbNoteSizeHistogram.bucketSeconds)
    private static let newest: UInt32 = 1700000000
    private static let middle: UInt32 = newest - day
    private static let oldest: UInt32 = newest - 2 * day
    /// The start of each of those days, which is where a cutoff can land.
    private static func startOfDay(_ timestamp: UInt32) -> UInt32 {
        return (timestamp / day) * day
    }

    private func histogram(_ entries: [(UInt32, UInt64)]) -> NdbNoteSizeHistogram {
        var histogram = NdbNoteSizeHistogram()
        for (createdAt, bytes) in entries {
            histogram.add(createdAt: createdAt, bytes: bytes)
        }
        return histogram
    }

    func test_histogram_buckets_by_utc_day() throws {
        let day = Self.day
        let histogram = self.histogram([
            (Self.newest, 10),
            (Self.newest + 5, 20),   // same day as the one above
            (Self.middle, 30),
        ])

        XCTAssertEqual(histogram.noteCount, 3)
        XCTAssertEqual(histogram.totalBytes, 60)
        XCTAssertEqual(histogram.bytesPerDay, [Self.newest / day: 30, Self.middle / day: 30],
                       "notes on the same UTC day share a bucket")
    }

    func test_since_cutoff_is_nil_when_the_whole_database_fits() throws {
        let histogram = self.histogram([(Self.newest, 10), (Self.oldest, 10)])
        XCTAssertNil(histogram.sinceCutoff(keepingAtMost: 20),
                     "a budget the database already meets needs no since filter")
        XCTAssertNil(histogram.sinceCutoff(keepingAtMost: 1000))
    }

    func test_since_cutoff_is_nil_for_an_empty_database() throws {
        XCTAssertNil(NdbNoteSizeHistogram().sinceCutoff(keepingAtMost: 0))
    }

    func test_since_cutoff_stops_before_the_day_that_would_blow_the_budget() throws {
        let histogram = self.histogram([
            (Self.newest, 10),
            (Self.middle, 10),
            (Self.oldest, 10),
        ])

        // Room for the two newest days but not the third.
        XCTAssertEqual(histogram.sinceCutoff(keepingAtMost: 25), Self.startOfDay(Self.middle))
        // Exactly the two newest days.
        XCTAssertEqual(histogram.sinceCutoff(keepingAtMost: 20), Self.startOfDay(Self.middle))
        // Room for one day only.
        XCTAssertEqual(histogram.sinceCutoff(keepingAtMost: 10), Self.startOfDay(Self.newest))
    }

    func test_since_cutoff_keeps_the_newest_day_even_when_it_alone_overshoots() throws {
        let histogram = self.histogram([(Self.newest, 100), (Self.oldest, 1)])

        XCTAssertEqual(histogram.sinceCutoff(keepingAtMost: 1), Self.startOfDay(Self.newest),
                       "day granularity cannot split the newest day, and keeping nothing would be worse")
    }

    func test_since_cutoff_skips_over_days_with_no_notes() throws {
        let histogram = self.histogram([
            (Self.newest, 10),
            (Self.oldest - 100 * Self.day, 10),
        ])

        XCTAssertEqual(histogram.sinceCutoff(keepingAtMost: 10), Self.startOfDay(Self.newest),
                       "the walk visits populated days, not every day in between")
    }

    // MARK: - Ndb.noteSizeHistogram

    func test_note_size_histogram_counts_every_note_in_the_database() throws {
        let ndb = try seeded(with: [
            try profile("alice", alice, at: Self.newest),
            try note("alice one", alice, at: Self.newest),
            try note("bob one", bob, at: Self.middle),
            try note("bob two", bob, at: Self.oldest),
        ])
        defer { ndb.close() }

        let histogram = try ndb.noteSizeHistogram()

        XCTAssertEqual(histogram.noteCount, 4, "kind-0 profiles are notes too, and are counted")
        XCTAssertEqual(Set(histogram.bytesPerDay.keys),
                       [Self.newest / Self.day, Self.middle / Self.day, Self.oldest / Self.day])
        XCTAssertEqual(histogram.bytesPerDay.values.reduce(0, +), histogram.totalBytes,
                       "the buckets have to add up to the total")
        XCTAssertGreaterThan(histogram.totalBytes, 0)
    }

    func test_note_size_histogram_of_an_empty_database_is_empty() throws {
        let ndb = try seeded(with: [])
        defer { ndb.close() }

        let histogram = try ndb.noteSizeHistogram()
        XCTAssertEqual(histogram.noteCount, 0)
        XCTAssertEqual(histogram.totalBytes, 0)
        XCTAssertTrue(histogram.bytesPerDay.isEmpty)
    }

    // MARK: - NdbFilterArray.pruneFilters

    func test_prune_filters_with_a_cutoff_fills_the_spare_slot() throws {
        let filters = try NdbFilterArray.pruneFilters(keeping: [alice.pubkey], since: Self.middle)
        XCTAssertEqual(filters.count, Int(NDB_PRUNE_DEFAULT_FILTERS) + 1)
        XCTAssertEqual(filters.count, filters.capacity, "the cutoff goes in the slot left spare for it")
    }

    func test_prune_filters_cutoff_drops_older_notes_but_not_our_own() throws {
        let ndb = try seeded(with: [
            try note("alice old", alice, at: Self.oldest),
            try note("bob old", bob, at: Self.oldest),
            try note("bob new", bob, at: Self.newest),
        ])
        defer { ndb.close() }

        let filters = try NdbFilterArray.pruneFilters(keeping: [alice.pubkey],
                                                      since: Self.startOfDay(Self.newest))
        try ndb.prune(to: outputDir, filters: filters)

        XCTAssertEqual(try contents(inDatabaseAt: outputDir, kind: .text),
                       ["alice old", "bob new"],
                       "filters are unioned, so our own notes survive the cutoff that drops everyone else's")
    }

    // MARK: - The whole thing: budget in, pruned database out

    func test_a_computed_cutoff_prunes_down_to_the_budget() throws {
        // Equal-length contents so each day weighs the same, and no notes by the
        // pubkeys we keep, so the cutoff is the only thing deciding what stays.
        let ndb = try seeded(with: [
            try note("note-newest", bob, at: Self.newest),
            try note("note-middle", bob, at: Self.middle),
            try note("note-oldest", bob, at: Self.oldest),
        ])
        defer { ndb.close() }

        let histogram = try ndb.noteSizeHistogram()
        let budget = (histogram.bytesPerDay[Self.newest / Self.day] ?? 0)
                   + (histogram.bytesPerDay[Self.middle / Self.day] ?? 0)

        let cutoff = try XCTUnwrap(ndb.pruneSinceCutoff(keepingAtMost: budget))
        XCTAssertEqual(cutoff, Self.startOfDay(Self.middle))

        try ndb.prune(to: outputDir, filters: try XCTUnwrap(ndb.pruneFilters(keeping: [], budget: budget)))

        XCTAssertEqual(try contents(inDatabaseAt: outputDir, kind: .text),
                       ["note-middle", "note-newest"],
                       "the note from the day the budget could not afford is gone")

        let pruned = try XCTUnwrap(Ndb(path: outputDir, owns_db_file: false))
        defer { pruned.close() }
        XCTAssertLessThanOrEqual(try pruned.noteSizeHistogram().totalBytes, budget,
                                 "the pruned database should land at or under the budget it was sized for")
    }

    func test_a_budget_the_database_already_meets_asks_for_no_prune_at_all() throws {
        let ndb = try seeded(with: [
            try note("bob old", bob, at: Self.oldest),
            try note("bob new", bob, at: Self.newest),
        ])
        defer { ndb.close() }

        XCTAssertNil(try ndb.pruneSinceCutoff(keepingAtMost: 10_000_000))
        // Not "prune with the defaults": those keep only profiles and our own
        // notes, so pruning with them would drop both of bob's notes even though
        // the database was comfortably under budget.
        XCTAssertNil(try ndb.pruneFilters(keeping: [], budget: 10_000_000))
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
