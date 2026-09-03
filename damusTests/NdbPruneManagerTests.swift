//
//  NdbPruneManagerTests.swift
//  damusTests
//
//  Covers the runtime prune runner: when it decides to prune, and that a prune
//  it runs leaves a valid database staged with a marker pointing at it.
//

import XCTest
@testable import damus

final class NdbPruneManagerTests: XCTestCase {
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

    /// Ingests `events` and hands back a freshly opened `Ndb`, the seeding one
    /// having been closed so its writer drained.
    private func seeded(with events: [NostrEvent]) throws -> Ndb {
        let seeder = try XCTUnwrap(Ndb(path: dbDir))
        XCTAssertTrue(seeder.process_events(wire(events)))
        seeder.close()
        return try XCTUnwrap(Ndb(path: dbDir))
    }

    private func contents(of ndb: Ndb) throws -> [String] {
        let filter = try NdbFilter(from: NostrFilter(kinds: [.text]))
        let keys = try ndb.query(filters: [filter], maxResults: 100)
        return try ndb.compact_map_notes(keys: keys, { _, note in note.content }).sorted()
    }

    private func contents(inDatabaseAt path: String) throws -> [String] {
        let ndb = try XCTUnwrap(Ndb(path: path, owns_db_file: false))
        defer { ndb.close() }
        return try contents(of: ndb)
    }

    // MARK: - The decision

    private let gb: UInt64 = 1024 * 1024 * 1024

    /// Free space that clears the margin for any tier used here.
    private var plentyOfSpace: UInt64 { return 64 * 1024 * 1024 * 1024 }

    func test_an_unlimited_budget_never_prunes() {
        let decision = NdbPruneManager.decide(databaseSizeBytes: 100 * gb,
                                              budget: .unlimited,
                                              pendingPrune: nil,
                                              availableBytes: plentyOfSpace,
                                              lastFailure: nil)
        XCTAssertEqual(decision, .noBudget, "unlimited is the opt-out, however big the database gets")
    }

    func test_a_database_under_the_trigger_is_left_alone() throws {
        // The trigger sits below the budget so the database has room to grow
        // while a prune runs.
        let budget = try XCTUnwrap(NdbSpaceBudget.small.bytes)
        let trigger = UInt64(Double(budget) * NdbPruneManager.triggerFraction)

        XCTAssertEqual(NdbPruneManager.decide(databaseSizeBytes: trigger,
                                              budget: .small,
                                              pendingPrune: nil,
                                              availableBytes: plentyOfSpace,
                                              lastFailure: nil),
                       .underBudget(sizeBytes: trigger, triggerBytes: trigger))
    }

    func test_a_database_over_the_trigger_prunes_to_below_the_budget() throws {
        let budget = try XCTUnwrap(NdbSpaceBudget.small.bytes)
        let expectedTarget = UInt64(Double(budget) * NdbPruneManager.targetFraction)

        let decision = NdbPruneManager.decide(databaseSizeBytes: budget + 1,
                                              budget: .small,
                                              pendingPrune: nil,
                                              availableBytes: plentyOfSpace,
                                              lastFailure: nil)

        XCTAssertEqual(decision, .prune(fileBudget: expectedTarget))
        XCTAssertLessThan(expectedTarget, budget,
                          "the prune aims under the budget, or it would trip the trigger again immediately")
    }

    func test_a_staged_prune_stops_another_one_starting() {
        let pending = NdbPendingPrune(path: "/tmp/staged", completedAt: Date())
        XCTAssertEqual(NdbPruneManager.decide(databaseSizeBytes: 10 * gb,
                                              budget: .small,
                                              pendingPrune: pending,
                                              availableBytes: plentyOfSpace,
                                              lastFailure: nil),
                       .alreadyPending,
                       "pruning again would throw away work for a database that is about to be replaced")
    }

    func test_a_recent_failure_backs_off() {
        let now = Date()
        let failedAt = now.addingTimeInterval(-60)

        let decision = NdbPruneManager.decide(databaseSizeBytes: 10 * gb,
                                              budget: .small,
                                              pendingPrune: nil,
                                              availableBytes: plentyOfSpace,
                                              lastFailure: failedAt,
                                              now: now)

        XCTAssertEqual(decision, .backingOff(until: failedAt.addingTimeInterval(NdbPruneManager.failureBackoff)))
    }

    func test_the_backoff_expires() {
        let now = Date()
        let failedAt = now.addingTimeInterval(-NdbPruneManager.failureBackoff - 1)

        guard case .prune = NdbPruneManager.decide(databaseSizeBytes: 10 * gb,
                                                   budget: .small,
                                                   pendingPrune: nil,
                                                   availableBytes: plentyOfSpace,
                                                   lastFailure: failedAt,
                                                   now: now) else {
            return XCTFail("a failure older than the backoff should not hold a prune off forever")
        }
    }

    func test_a_full_disk_stops_a_prune_that_could_not_finish() {
        // Source and pruned copy have to coexist, so there has to be room for
        // the output plus a margin.
        let decision = NdbPruneManager.decide(databaseSizeBytes: 10 * gb,
                                              budget: .small,
                                              pendingPrune: nil,
                                              availableBytes: 1024,
                                              lastFailure: nil)

        guard case .notEnoughFreeSpace(let needed, let available) = decision else {
            return XCTFail("expected notEnoughFreeSpace, got \(decision)")
        }
        XCTAssertEqual(available, 1024)
        XCTAssertGreaterThan(needed, NdbPruneManager.freeSpaceMarginBytes,
                             "the requirement is the estimated output on top of the margin")
    }

    func test_free_space_the_volume_will_not_report_does_not_block_a_prune() {
        // The prune fails cleanly if the disk fills; refusing on an unknown would
        // mean never pruning on a volume that does not answer.
        guard case .prune = NdbPruneManager.decide(databaseSizeBytes: 10 * gb,
                                                   budget: .small,
                                                   pendingPrune: nil,
                                                   availableBytes: nil,
                                                   lastFailure: nil) else {
            return XCTFail("an unknown free-space figure should not stop a prune")
        }
    }

    func test_no_database_is_nothing_to_prune() {
        XCTAssertEqual(NdbPruneManager.decide(databaseSizeBytes: nil,
                                              budget: .small,
                                              pendingPrune: nil,
                                              availableBytes: plentyOfSpace,
                                              lastFailure: nil),
                       .noDatabase)
    }

    // MARK: - Scaling the budget

    func test_the_note_budget_is_the_file_budget_scaled_by_what_notes_take_up() {
        // A database where notes are a tenth of the file: a tenth of the file
        // budget is what the histogram — which counts only notes — should get.
        XCTAssertEqual(NdbPruneManager.noteBudget(forFileBudget: 1000,
                                                  databaseSizeBytes: 1000,
                                                  noteBytes: 100),
                       100)
        XCTAssertEqual(NdbPruneManager.noteBudget(forFileBudget: 500,
                                                  databaseSizeBytes: 1000,
                                                  noteBytes: 100),
                       50)
    }

    func test_the_note_budget_does_not_overflow_on_a_real_sized_database() {
        // The integer form of this — fileBudget * noteBytes / size — overflows
        // UInt64 for any real database, since both terms run to gigabytes.
        let budget = 8 * gb
        let size = 10 * gb
        let notes = 4 * gb

        let noteBudget = NdbPruneManager.noteBudget(forFileBudget: budget,
                                                    databaseSizeBytes: size,
                                                    noteBytes: notes)

        XCTAssertEqual(noteBudget, UInt64((Double(budget) / Double(size) * Double(notes)).rounded()))
        XCTAssertLessThan(noteBudget, notes, "keeping less than everything is the whole point")
    }

    func test_a_database_of_no_size_scales_to_everything_rather_than_dividing_by_zero() {
        XCTAssertEqual(NdbPruneManager.noteBudget(forFileBudget: 1000,
                                                  databaseSizeBytes: 0,
                                                  noteBytes: 100),
                       100)
    }

    // MARK: - Running one

    func test_a_prune_stages_a_valid_database_and_marks_it_pending() async throws {
        let ndb = try seeded(with: [
            try note("alice old", alice, at: Self.newest - 2 * Self.day),
            try note("bob old", bob, at: Self.newest - 2 * Self.day),
            try note("bob new", bob, at: Self.newest),
        ])
        defer { ndb.close() }

        let manager = NdbPruneManager(ndb: ndb, keepAuthors: [alice.pubkey], dbPath: dbDir)

        // A budget of one byte: everything the cutoff can drop, it drops. The
        // trigger and the free-space check are covered above; this is about what
        // a prune leaves behind.
        let staged = try await manager.stagePrune(fileBudget: 1)
        let stagedPath = try XCTUnwrap(staged, "a database this far over budget should have produced a prune")

        XCTAssertEqual(stagedPath, "\(dbDir)/\(NdbPruneManager.stagedDirectoryName)",
                       "the staged copy lives beside the database, not in tmp, so it survives to the next launch")
        XCTAssertTrue(Ndb.db_file_exists(path: stagedPath), "the staged directory should hold a database")
        XCTAssertNil(Ndb.get_pending_prune(),
                     "staging on its own must not arm a swap — only a full pruneIfNeeded does that")

        // The staged database is a real one, and the keep-policy held: our own
        // notes survived the cutoff that dropped everyone else's.
        XCTAssertEqual(try contents(inDatabaseAt: stagedPath), ["alice old", "bob new"])

        // And the live database is untouched.
        XCTAssertEqual(try contents(of: ndb), ["alice old", "bob new", "bob old"])
    }

    func test_acting_on_a_prune_decision_marks_the_result_pending() async throws {
        let ndb = try seeded(with: [
            try note("bob old", bob, at: Self.newest - 2 * Self.day),
            try note("bob new", bob, at: Self.newest),
        ])
        defer { ndb.close() }

        let manager = NdbPruneManager(ndb: ndb, keepAuthors: [], dbPath: dbDir)
        let didPrune = try await manager.prune(if: .prune(fileBudget: 1))

        XCTAssertTrue(didPrune)
        let marker = try XCTUnwrap(Ndb.get_pending_prune(), "a completed prune has to leave a marker behind")
        XCTAssertEqual(marker.path, "\(dbDir)/\(NdbPruneManager.stagedDirectoryName)")
        XCTAssertLessThan(abs(marker.completedAt.timeIntervalSinceNow), 60)
        XCTAssertTrue(Ndb.db_file_exists(path: marker.path), "the marker has to name a database that is really there")

        let count = await manager.pruneCount
        XCTAssertEqual(count, 1)
    }

    func test_a_decision_not_to_prune_does_nothing_at_all() async throws {
        let ndb = try seeded(with: [try note("bob new", bob, at: Self.newest)])
        defer { ndb.close() }

        let manager = NdbPruneManager(ndb: ndb, keepAuthors: [], dbPath: dbDir)

        for decision in [NdbPruneManager.Decision.noBudget,
                         .underBudget(sizeBytes: 1, triggerBytes: 2),
                         .alreadyPending,
                         .noDatabase] {
            let didPrune = try await manager.prune(if: decision)
            XCTAssertFalse(didPrune, "\(decision) should not have started a prune")
        }

        XCTAssertNil(Ndb.get_pending_prune())
        XCTAssertFalse(FileManager.default.fileExists(atPath: "\(dbDir)/\(NdbPruneManager.stagedDirectoryName)"))
    }

    func test_a_failed_prune_backs_off_before_trying_again() async throws {
        let ndb = try seeded(with: [try note("bob new", bob, at: Self.newest)])
        ndb.close()

        let manager = NdbPruneManager(ndb: ndb, keepAuthors: [], dbPath: dbDir)
        do {
            _ = try await manager.prune(if: .prune(fileBudget: 1))
            XCTFail("a prune against a closed database should not report success")
        } catch {
            // Expected.
        }

        // The failure is remembered, so the next check that would otherwise
        // prune waits instead of retrying a minutes-long job immediately.
        let lastFailure = await manager.lastFailure
        let failedAt = try XCTUnwrap(lastFailure, "a failed prune has to be remembered")
        XCTAssertLessThan(abs(failedAt.timeIntervalSinceNow), 60)

        let decision = NdbPruneManager.decide(databaseSizeBytes: 10 * gb,
                                              budget: .small,
                                              pendingPrune: nil,
                                              availableBytes: plentyOfSpace,
                                              lastFailure: failedAt)
        guard case .backingOff = decision else {
            return XCTFail("expected the remembered failure to back off, got \(decision)")
        }
    }

    func test_a_prune_leaves_nothing_staged_when_the_notes_already_fit() async throws {
        let ndb = try seeded(with: [try note("bob new", bob, at: Self.newest)])
        defer { ndb.close() }

        let manager = NdbPruneManager(ndb: ndb, keepAuthors: [alice.pubkey], dbPath: dbDir)

        // A budget far bigger than the notes: there is no cutoff to compute, so
        // there is nothing to stage — and nothing may be marked pending, or the
        // swap would replace a good database with an absent one.
        let staged = try await manager.stagePrune(fileBudget: 100 * gb)

        XCTAssertNil(staged)
        XCTAssertNil(Ndb.get_pending_prune())
        XCTAssertFalse(FileManager.default.fileExists(atPath: "\(dbDir)/\(NdbPruneManager.stagedDirectoryName)"),
                       "an attempt that staged nothing must not leave a directory behind")
    }

    func test_a_prune_clears_the_wreckage_of_an_abandoned_attempt() async throws {
        let ndb = try seeded(with: [
            try note("bob old", bob, at: Self.newest - 2 * Self.day),
            try note("bob new", bob, at: Self.newest),
        ])
        defer { ndb.close() }

        // A directory left by an attempt that never finished — the app was
        // backgrounded mid-prune, say. LMDB refuses a destination that is not
        // empty, so a prune that did not clear this would fail forever.
        let stagedPath = "\(dbDir)/\(NdbPruneManager.stagedDirectoryName)"
        try FileManager.default.createDirectory(atPath: stagedPath, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: "\(stagedPath)/data.mdb", contents: Data("junk".utf8))

        let manager = NdbPruneManager(ndb: ndb, keepAuthors: [], dbPath: dbDir)
        let staged = try await manager.stagePrune(fileBudget: 1)

        XCTAssertEqual(staged, stagedPath)
        XCTAssertEqual(try contents(inDatabaseAt: stagedPath), ["bob new"],
                       "the staged database should be the new prune, not the leftovers")
    }

    func test_a_failed_prune_leaves_no_staged_directory_for_the_swap_to_find() async throws {
        let ndb = try seeded(with: [try note("bob new", bob, at: Self.newest)])
        // Closing the database makes the prune fail: withNdb refuses once closed.
        ndb.close()

        let manager = NdbPruneManager(ndb: ndb, keepAuthors: [], dbPath: dbDir)

        do {
            _ = try await manager.stagePrune(fileBudget: 1)
            XCTFail("a prune against a closed database should not report success")
        } catch {
            // Expected.
        }

        XCTAssertNil(Ndb.get_pending_prune(), "a failed prune must never leave a marker")
        XCTAssertFalse(FileManager.default.fileExists(atPath: "\(dbDir)/\(NdbPruneManager.stagedDirectoryName)"),
                       "a partial copy left where the swap could find it would be swapped in")
    }
}
