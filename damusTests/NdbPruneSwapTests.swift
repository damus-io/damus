//
//  NdbPruneSwapTests.swift
//  damusTests
//
//  Covers the launch-time swap: that a good staged prune replaces the live
//  database, and — the part that matters — that a bad one never does.
//

import XCTest
@testable import damus

final class NdbPruneSwapTests: XCTestCase {
    var dbDir: String = ""

    let alice = generate_new_keypair()
    let bob = generate_new_keypair()

    /// A day wide enough apart that each note lands in its own histogram bucket.
    static let day = UInt32(NdbNoteSizeHistogram.bucketSeconds)
    static let newest: UInt32 = 1700000000

    override func setUpWithError() throws {
        dbDir = try XCTUnwrap(test_ndb_dir(), "could not create a database directory")
        UserDefaults.standard.removeObject(forKey: Ndb.space_budget_key)
        Ndb.clear_pending_prune()
    }

    override func tearDownWithError() throws {
        if !dbDir.isEmpty { try? FileManager.default.removeItem(atPath: dbDir) }
        UserDefaults.standard.removeObject(forKey: Ndb.space_budget_key)
        Ndb.clear_pending_prune()
    }

    // MARK: - Fixtures

    private var stagedPath: String { return "\(dbDir)/\(Ndb.staged_prune_directory_name)" }

    private func wire(_ events: [NostrEvent]) -> String {
        return events.compactMap({ encode_json($0) }).map({ "[\"EVENT\",\"s\",\($0)]\n" }).joined()
    }

    private func note(_ content: String, _ keypair: FullKeypair, at timestamp: UInt32) throws -> NostrEvent {
        return try XCTUnwrap(NostrEvent(content: content,
                                        keypair: keypair.to_keypair(),
                                        kind: 1,
                                        tags: [],
                                        createdAt: timestamp))
    }

    private func profile(_ name: String, _ keypair: FullKeypair, at timestamp: UInt32) throws -> NostrEvent {
        return try XCTUnwrap(NostrEvent(content: "{\"name\":\"\(name)\"}",
                                        keypair: keypair.to_keypair(),
                                        kind: 0,
                                        tags: [],
                                        createdAt: timestamp))
    }

    /// Ingests `events` into the database at `path` and closes it, so the writer
    /// has drained and `data.mdb` is complete — which is the state both the live
    /// database and a staged copy are in when a swap happens.
    private func ingest(_ events: [NostrEvent], into path: String) throws {
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        let ndb = try XCTUnwrap(Ndb(path: path))
        XCTAssertTrue(ndb.process_events(wire(events)))
        ndb.close()
    }

    private func contents(inDatabaseAt path: String) throws -> [String] {
        let ndb = try XCTUnwrap(Ndb(path: path, owns_db_file: false))
        defer { ndb.close() }
        let filter = try NdbFilter(from: NostrFilter(kinds: [.text]))
        let keys = try ndb.query(filters: [filter], maxResults: 100)
        return try ndb.compact_map_notes(keys: keys, { _, note in note.content }).sorted()
    }

    /// Arms a swap by hand, the way a completed prune would.
    private func markPending(promise: NdbPrunePromise, completedAt: Date = Date(), path: String? = nil) {
        Ndb.set_pending_prune(NdbPendingPrune(path: path ?? stagedPath,
                                              completedAt: completedAt,
                                              promise: promise))
    }

    /// A promise nothing in these fixtures can fail, for the tests that are
    /// about the swap rather than about validation.
    private var permissivePromise: NdbPrunePromise {
        return NdbPrunePromise(hasProfiles: false, authorsWithPosts: [], since: 0)
    }

    // MARK: - Nothing to do

    func test_no_marker_leaves_the_database_alone() throws {
        try ingest([try note("bob new", bob, at: Self.newest)], into: dbDir)

        XCTAssertEqual(Ndb.swap_staged_prune(db_path: dbDir), .nothingStaged)
        XCTAssertEqual(try contents(inDatabaseAt: dbDir), ["bob new"])
    }

    func test_a_marker_for_another_database_is_left_completely_alone() throws {
        try ingest([try note("bob new", bob, at: Self.newest)], into: dbDir)

        // The marker lives in UserDefaults, which is process-wide, while a
        // process opens several databases — the read-only snapshot, a test's
        // temp directory. Swapping a copy over the wrong one would be the worst
        // kind of bug this code could have.
        let elsewhere = "\(dbDir)-other/\(Ndb.staged_prune_directory_name)"
        markPending(promise: permissivePromise, path: elsewhere)

        XCTAssertEqual(Ndb.swap_staged_prune(db_path: dbDir), .notForThisDatabase(stagedPath: elsewhere))
        XCTAssertEqual(try contents(inDatabaseAt: dbDir), ["bob new"])
        XCTAssertNotNil(Ndb.get_pending_prune(), "the marker belongs to another database, so it must survive")
    }

    // MARK: - The happy path

    func test_a_staged_prune_is_swapped_in_and_the_marker_cleared() throws {
        try ingest([
            try note("alice old", alice, at: Self.newest - 2 * Self.day),
            try note("bob old", bob, at: Self.newest - 2 * Self.day),
            try note("bob new", bob, at: Self.newest),
        ], into: dbDir)

        // What a prune keeping alice since `newest` would have left behind.
        try ingest([
            try profile("alice", alice, at: Self.newest),
            try note("alice old", alice, at: Self.newest - 2 * Self.day),
            try note("bob new", bob, at: Self.newest),
        ], into: stagedPath)

        let stagedSize = try XCTUnwrap(Ndb.database_file_size(path: stagedPath))
        markPending(promise: NdbPrunePromise(hasProfiles: true,
                                             authorsWithPosts: [alice.pubkey],
                                             since: Self.newest))

        XCTAssertEqual(Ndb.swap_staged_prune(db_path: dbDir), .swapped(bytes: stagedSize))

        XCTAssertEqual(try contents(inDatabaseAt: dbDir), ["alice old", "bob new"],
                       "the live database should now be the pruned copy")
        XCTAssertNil(Ndb.get_pending_prune(), "a swapped-in copy must not be swapped in again")
        XCTAssertFalse(FileManager.default.fileExists(atPath: stagedPath),
                       "the staging directory should be gone, lock.mdb and all")
    }

    func test_the_swap_deletes_the_stale_lock_file() throws {
        try ingest([try note("bob old", bob, at: Self.newest - 2 * Self.day)], into: dbDir)
        try ingest([try note("bob new", bob, at: Self.newest)], into: stagedPath)
        markPending(promise: permissivePromise)

        // Whatever `lock.mdb` the last session left describes readers and
        // transactions pointing into pages of the *old* data.mdb. Left in place
        // across the swap it is a SIGBUS waiting for the next open, so the swap
        // has to delete it and let LMDB build a fresh one.
        let lockPath = "\(dbDir)/lock.mdb"
        XCTAssertTrue(FileManager.default.fileExists(atPath: lockPath),
                      "the ingest above should have left a lock file to clear")

        guard case .swapped = Ndb.swap_staged_prune(db_path: dbDir) else {
            return XCTFail("expected the swap to go through")
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: lockPath),
                       "the stale lock file has to go before anything maps the new data.mdb")
    }

    func test_opening_the_database_swaps_a_staged_prune_in_first() throws {
        try ingest([
            try note("bob old", bob, at: Self.newest - 2 * Self.day),
            try note("bob new", bob, at: Self.newest),
        ], into: dbDir)
        try ingest([try note("bob new", bob, at: Self.newest)], into: stagedPath)
        markPending(promise: permissivePromise)

        // The swap hangs off `Ndb.open` so that "before nostrdb maps anything"
        // is structurally true rather than a convention a caller has to follow.
        // That is the property under test here.
        Ndb.reset_staged_prune_swap_state_for_testing()
        let ndb = try XCTUnwrap(Ndb(path: dbDir))
        defer { ndb.close() }

        let filter = try NdbFilter(from: NostrFilter(kinds: [.text]))
        let keys = try ndb.query(filters: [filter], maxResults: 100)
        let contents = try ndb.compact_map_notes(keys: keys, { _, note in note.content }).sorted()

        XCTAssertEqual(contents, ["bob new"], "the database that opened should be the pruned one")
        XCTAssertNil(Ndb.get_pending_prune())
        guard case .swapped = Ndb.staged_prune_swap_outcome else {
            return XCTFail("the open should have recorded a swap, got \(String(describing: Ndb.staged_prune_swap_outcome))")
        }
    }

    // MARK: - Refusing a bad copy

    func test_a_marker_whose_staged_database_vanished_is_cleaned_up() throws {
        try ingest([try note("bob new", bob, at: Self.newest)], into: dbDir)

        // iOS can delete files underneath us, and a swap interrupted between the
        // move and clearing the marker lands here too.
        markPending(promise: permissivePromise)

        XCTAssertEqual(Ndb.swap_staged_prune(db_path: dbDir),
                       .refused(.missingOrEmpty(path: stagedPath)))
        XCTAssertEqual(try contents(inDatabaseAt: dbDir), ["bob new"])
        XCTAssertNil(Ndb.get_pending_prune(), "a marker naming nothing has to be forgotten, or it is retried forever")
    }

    func test_a_stale_staged_prune_is_refused_and_binned() throws {
        try ingest([
            try note("bob old", bob, at: Self.newest - 2 * Self.day),
            try note("bob new", bob, at: Self.newest),
        ], into: dbDir)
        try ingest([try note("bob new", bob, at: Self.newest)], into: stagedPath)

        // Swapping this in would throw away everything ingested since it was
        // made, which by now is more than the prune saved.
        let age = Ndb.staged_prune_expiry + 60
        markPending(promise: permissivePromise, completedAt: Date().addingTimeInterval(-age))

        guard case .refused(.tooStale) = Ndb.swap_staged_prune(db_path: dbDir) else {
            return XCTFail("expected an expired copy to be refused")
        }

        XCTAssertEqual(try contents(inDatabaseAt: dbDir), ["bob new", "bob old"],
                       "the live database keeps everything it had")
        XCTAssertNil(Ndb.get_pending_prune())
        XCTAssertFalse(FileManager.default.fileExists(atPath: stagedPath),
                       "a copy we will not use is a copy to delete — the next prune stages a fresh one")
    }

    func test_a_copy_a_fraction_of_the_size_of_the_live_database_is_refused() throws {
        try ingest([try note("bob new", bob, at: Self.newest)], into: stagedPath)
        let stagedSize = try XCTUnwrap(Ndb.database_file_size(path: stagedPath))

        // Standing in for the real shape of this failure: a prune of a
        // multi-gigabyte database that produced a valid, nearly empty one.
        let liveSize: UInt64 = 100 * 1024 * 1024 * 1024
        let pending = NdbPendingPrune(path: stagedPath, completedAt: Date(), promise: permissivePromise)
        let floor = UInt64(Double(liveSize) * Ndb.minimum_staged_prune_fraction)

        XCTAssertEqual(Ndb.evaluate_staged_prune(pending, liveSizeBytes: liveSize),
                       .tooSmall(bytes: stagedSize, floor: floor))

        // The same copy against a database its own size is perfectly fine, which
        // is the point of expressing the floor as a ratio.
        XCTAssertNil(Ndb.evaluate_staged_prune(pending, liveSizeBytes: stagedSize))
    }

    func test_a_copy_missing_the_promised_profiles_is_refused() throws {
        try ingest([
            try note("bob old", bob, at: Self.newest - 2 * Self.day),
            try note("bob new", bob, at: Self.newest),
        ], into: dbDir)

        // A valid database with plenty in it, but the keep-policy promised every
        // kind-0 profile in the source and this has none of them. Only the prune
        // can drop profiles, so this cannot be anything but a broken prune.
        try ingest([try note("bob new", bob, at: Self.newest)], into: stagedPath)
        markPending(promise: NdbPrunePromise(hasProfiles: true, authorsWithPosts: [], since: 0))

        XCTAssertEqual(Ndb.swap_staged_prune(db_path: dbDir), .refused(.noProfiles))
        XCTAssertEqual(try contents(inDatabaseAt: dbDir), ["bob new", "bob old"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: stagedPath))
    }

    func test_a_copy_missing_our_own_notes_is_refused() throws {
        try ingest([
            try note("alice says hello", alice, at: Self.newest - 2 * Self.day),
            try note("bob new", bob, at: Self.newest),
        ], into: dbDir)

        // The policy keeps everything we authored regardless of age, so a copy
        // without it is a copy that ate the user's own posts.
        //
        // Alice's *profile* is in here on purpose. The profiles filter keeps it
        // whatever else goes wrong, so an author check that asked merely for
        // "some note by alice" would be answered by it and wave this through.
        try ingest([
            try profile("alice", alice, at: Self.newest),
            try note("bob new", bob, at: Self.newest),
        ], into: stagedPath)
        markPending(promise: NdbPrunePromise(hasProfiles: true, authorsWithPosts: [alice.pubkey], since: 0))

        XCTAssertEqual(Ndb.swap_staged_prune(db_path: dbDir), .refused(.missingAuthor(alice.pubkey)))
        XCTAssertEqual(try contents(inDatabaseAt: dbDir), ["alice says hello", "bob new"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: stagedPath))
    }

    func test_a_copy_with_nothing_after_the_cutoff_is_refused() throws {
        try ingest([
            try note("bob old", bob, at: Self.newest - 2 * Self.day),
            try note("bob new", bob, at: Self.newest),
        ], into: dbDir)

        // The cutoff always lands on the start of a day the source had notes in,
        // so a copy with nothing at or after it means the `since` filter did not
        // take — the bad-cutoff failure, which leaves profiles and our own notes
        // and nothing else.
        try ingest([
            try profile("alice", alice, at: Self.newest - 10 * Self.day),
            try note("alice ancient", alice, at: Self.newest - 10 * Self.day),
        ], into: stagedPath)
        markPending(promise: NdbPrunePromise(hasProfiles: true,
                                             authorsWithPosts: [alice.pubkey],
                                             since: Self.newest))

        XCTAssertEqual(Ndb.swap_staged_prune(db_path: dbDir),
                       .refused(.nothingAfterCutoff(since: Self.newest)))
        XCTAssertEqual(try contents(inDatabaseAt: dbDir), ["bob new", "bob old"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: stagedPath))
    }

    // MARK: - What the prune promises

    func test_the_promise_records_only_the_authors_the_source_has_posts_from() throws {
        try ingest([
            try profile("alice", alice, at: Self.newest),
            try profile("bob", bob, at: Self.newest),
            try note("bob new", bob, at: Self.newest),
        ], into: dbDir)

        let ndb = try XCTUnwrap(Ndb(path: dbDir))
        defer { ndb.close() }

        // Alice has a profile but has never posted. Promising her posts survive
        // would refuse every prune she ever stages, and quietly stop enforcing
        // her budget — so having a profile must not be enough to be recorded.
        let promise = try NdbPrunePromise(source: ndb,
                                          keepAuthors: [alice.pubkey, bob.pubkey],
                                          since: Self.newest)

        XCTAssertEqual(promise.authorsWithPosts, [bob.pubkey])
        XCTAssertTrue(promise.hasProfiles)
        XCTAssertEqual(promise.since, Self.newest)
    }

    func test_a_promise_survives_a_round_trip_through_the_marker() throws {
        let promise = NdbPrunePromise(hasProfiles: true,
                                      authorsWithPosts: [alice.pubkey, bob.pubkey],
                                      since: Self.newest)
        let completedAt = Date(timeIntervalSince1970: 1700000123)
        markPending(promise: promise, completedAt: completedAt)

        let read = try XCTUnwrap(Ndb.get_pending_prune())
        XCTAssertEqual(read, NdbPendingPrune(path: stagedPath, completedAt: completedAt, promise: promise))
    }

    func test_a_marker_with_no_promise_recorded_is_not_a_marker() throws {
        // A half-written marker cannot be validated, and the swap must never run
        // against a keep-policy it cannot read.
        UserDefaults.standard.set(stagedPath, forKey: Ndb.pending_prune_path_key)
        UserDefaults.standard.set(Date(), forKey: Ndb.pending_prune_completed_at_key)

        XCTAssertNil(Ndb.get_pending_prune())
        XCTAssertEqual(Ndb.swap_staged_prune(db_path: dbDir), .nothingStaged)
    }
}
