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

    static let day: UInt32 = 86_400
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
        return NdbPrunePromise(hasProfiles: false, authorsWithPosts: [])
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

    // MARK: - Pruning a database that is itself a prune output

    func test_a_second_prune_after_a_swap_succeeds() throws {
        // The field sequence from headway:damus-ios/mansion-grow-kite: prune
        // once, restart so the swap applies, then press the button again. Every
        // other test here fakes the staged copy with `ingest`, so nothing
        // covered a prune whose *source* is a database `ndb_prune` produced —
        // which is the one thing demonstrably different on a second run.
        try ingest([
            try profile("alice", alice, at: Self.newest),
            try profile("bob", bob, at: Self.newest),
            try note("alice one", alice, at: Self.newest - 2 * Self.day),
            try note("bob one", bob, at: Self.newest),
        ], into: dbDir)

        let promise = try stageRealPrune(from: dbDir, into: stagedPath, keeping: [alice.pubkey])
        markPending(promise: promise)
        guard case .swapped = Ndb.swap_staged_prune(db_path: dbDir) else {
            return XCTFail("the first prune should have been swapped in")
        }
        XCTAssertEqual(try contents(inDatabaseAt: dbDir), ["alice one"],
                       "the live database should now be a database ndb_prune wrote")

        // Second press. This is the one that failed on device with nothing but
        // a path to go on.
        _ = try stageRealPrune(from: dbDir, into: stagedPath, keeping: [alice.pubkey])

        XCTAssertEqual(try contents(inDatabaseAt: stagedPath), ["alice one"],
                       "pruning a prune output should keep what the policy keeps, not empty it")
    }

    /// Runs a real `ndb_prune` from `source` into `destination`, the way
    /// `NdbPruneManager.stagePrune` does, and hands back the promise it made.
    ///
    /// Unlike the `ingest`-based fixtures above, this exercises nostrdb itself,
    /// which is the only way to have a source database that `ndb_prune` wrote.
    @discardableResult
    private func stageRealPrune(from source: String, into destination: String,
                                keeping authors: [Pubkey]) throws -> NdbPrunePromise {
        let ndb = try XCTUnwrap(Ndb(path: source))
        defer { ndb.close() }

        try? FileManager.default.removeItem(atPath: destination)
        try FileManager.default.createDirectory(atPath: destination, withIntermediateDirectories: true)

        let filters = try NdbFilterArray.defaultPruneFilters(keeping: authors)
        let promise = try NdbPrunePromise(source: ndb, keepAuthors: authors)
        try ndb.prune(to: destination, filters: filters)
        return promise
    }

    // MARK: - The happy path

    func test_a_staged_prune_is_swapped_in_and_the_marker_cleared() throws {
        try ingest([
            try note("alice old", alice, at: Self.newest - 2 * Self.day),
            try note("bob old", bob, at: Self.newest - 2 * Self.day),
            try note("bob new", bob, at: Self.newest),
        ], into: dbDir)

        // What a prune keeping alice would have left behind: her profile, her
        // own notes, and nothing of bob's.
        try ingest([
            try profile("alice", alice, at: Self.newest),
            try note("alice old", alice, at: Self.newest - 2 * Self.day),
        ], into: stagedPath)

        let stagedSize = try XCTUnwrap(Ndb.database_file_size(path: stagedPath))
        markPending(promise: NdbPrunePromise(hasProfiles: true, authorsWithPosts: [alice.pubkey]))

        XCTAssertEqual(Ndb.swap_staged_prune(db_path: dbDir), .swapped(bytes: stagedSize))

        XCTAssertEqual(try contents(inDatabaseAt: dbDir), ["alice old"],
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

    func test_a_copy_a_tiny_fraction_of_the_live_database_is_not_refused_for_that_alone() throws {
        // The prune collapses the database to profiles and our own notes, so a
        // copy orders of magnitude smaller than what it replaces is the normal
        // outcome, not a suspicious one. Any size floor would refuse every
        // healthy prune of a large database — the promise checks below are what
        // tell a good small copy from an emptied one.
        try ingest([try note("bob new", bob, at: Self.newest)], into: stagedPath)
        let pending = NdbPendingPrune(path: stagedPath, completedAt: Date(), promise: permissivePromise)

        XCTAssertNil(Ndb.evaluate_staged_prune(pending))
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
        markPending(promise: NdbPrunePromise(hasProfiles: true, authorsWithPosts: []))

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
        markPending(promise: NdbPrunePromise(hasProfiles: true, authorsWithPosts: [alice.pubkey]))

        XCTAssertEqual(Ndb.swap_staged_prune(db_path: dbDir), .refused(.missingAuthor(alice.pubkey)))
        XCTAssertEqual(try contents(inDatabaseAt: dbDir), ["alice says hello", "bob new"])
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
        let promise = try NdbPrunePromise(source: ndb, keepAuthors: [alice.pubkey, bob.pubkey])

        XCTAssertEqual(promise.authorsWithPosts, [bob.pubkey])
        XCTAssertTrue(promise.hasProfiles)
    }

    func test_a_promise_survives_a_round_trip_through_the_marker() throws {
        let promise = NdbPrunePromise(hasProfiles: true,
                                      authorsWithPosts: [alice.pubkey, bob.pubkey])
        let completedAt = Date(timeIntervalSince1970: 1700000123)
        markPending(promise: promise, completedAt: completedAt)

        let read = try XCTUnwrap(Ndb.get_pending_prune())
        XCTAssertEqual(read, NdbPendingPrune(path: stagedPath, completedAt: completedAt, promise: promise))
    }

    func test_a_marker_with_no_version_stamp_is_not_a_marker() throws {
        try ingest([try note("bob new", bob, at: Self.newest)], into: dbDir)
        try ingest([try note("bob new", bob, at: Self.newest)], into: stagedPath)

        // A marker interrupted before its version stamp went down cannot be
        // validated, and the swap must never run against a keep-policy it cannot
        // read. The staged copy goes with it — the next check stages a fresh one.
        UserDefaults.standard.set(stagedPath, forKey: Ndb.pending_prune_path_key)
        UserDefaults.standard.set(Date(), forKey: Ndb.pending_prune_completed_at_key)

        XCTAssertNil(Ndb.get_pending_prune())
        XCTAssertEqual(Ndb.swap_staged_prune(db_path: dbDir), .nothingStaged)
        XCTAssertEqual(try contents(inDatabaseAt: dbDir), ["bob new"], "the live database is untouched")
        XCTAssertFalse(Ndb.has_pending_prune_residue(), "the unreadable marker has to be cleared, or it is retried forever")
        XCTAssertFalse(FileManager.default.fileExists(atPath: stagedPath))
    }

    func test_a_marker_written_before_the_keep_policy_lost_its_cutoff_is_discarded() throws {
        try ingest([
            try note("bob old", bob, at: Self.newest - 2 * Self.day),
            try note("bob new", bob, at: Self.newest),
        ], into: dbDir)
        try ingest([try note("bob new", bob, at: Self.newest)], into: stagedPath)

        // Exactly what an install updating from the version that computed a
        // `since` cutoff carries: a marker with no version stamp and a `since`
        // key. Its copy was staged under a keep-policy this code cannot check,
        // so it must never be swapped in on today's weaker validation.
        UserDefaults.standard.set(stagedPath, forKey: Ndb.pending_prune_path_key)
        UserDefaults.standard.set(Date(), forKey: Ndb.pending_prune_completed_at_key)
        UserDefaults.standard.set(true, forKey: Ndb.pending_prune_has_profiles_key)
        UserDefaults.standard.set(NSNumber(value: Self.newest), forKey: "ndb_pending_prune_since")

        XCTAssertEqual(Ndb.swap_staged_prune(db_path: dbDir), .nothingStaged)
        XCTAssertEqual(try contents(inDatabaseAt: dbDir), ["bob new", "bob old"],
                       "the live database keeps everything it had")
        XCTAssertFalse(FileManager.default.fileExists(atPath: stagedPath))
        XCTAssertNil(UserDefaults.standard.object(forKey: "ndb_pending_prune_since"),
                     "the legacy key has to be swept too, or every launch rediscovers this marker")
    }

    func test_unreadable_marker_residue_for_another_database_leaves_that_directory_alone() throws {
        try ingest([try note("bob new", bob, at: Self.newest)], into: stagedPath)

        // The marker is process-wide. A version 1 marker naming some other
        // database's staging directory still has to stop being honoured, but
        // deleting a directory this open knows nothing about is not ours to do.
        let elsewhere = "\(dbDir)-other/\(Ndb.staged_prune_directory_name)"
        UserDefaults.standard.set(elsewhere, forKey: Ndb.pending_prune_path_key)
        UserDefaults.standard.set(Date(), forKey: Ndb.pending_prune_completed_at_key)

        XCTAssertEqual(Ndb.swap_staged_prune(db_path: dbDir), .nothingStaged)
        XCTAssertFalse(Ndb.has_pending_prune_residue())
        XCTAssertTrue(FileManager.default.fileExists(atPath: stagedPath),
                      "this database's staging directory is not the one the residue named")
    }
}
