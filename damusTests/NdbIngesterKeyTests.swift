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
/// Also covers the read side of the unwrap: that a rumor nostrdb peeled out of a real
/// giftwrap comes back from a plain `kinds: [14]` query and from a live subscription, and
/// that it is flagged as a rumor with the receiver and wrap recoverable from it.
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

    // MARK: The unwrapped rumor on the read path

    /// The whole point of the epic: with our key registered, an inbound kind-1059 is peeled
    /// in the ingester and the kind-14 rumor inside it is stored as an ordinary note — so a
    /// plain `kinds: [14]` query finds it, with no Swift-side decryption anywhere.
    func testUnwrappedRumorComesBackFromAPlainKind14Query() throws {
        let receiver = generate_new_keypair()
        let sender = generate_new_keypair()
        let wrap = try Self.giftwrap(content: "the rumor made it through",
                                     from: sender, to: receiver, sentAt: 1_700_000_000)

        let ndb = try Self.ingest(wrap, unwrappingWith: receiver)
        defer { ndb.close() }

        let filter = try NdbFilter(from: NostrFilter(kinds: [.private_dm]))
        let keys = try ndb.query(filters: [filter], maxResults: 10)
        XCTAssertEqual(keys.count, 1, "the unwrapped rumor should be in the kind index")

        let rumor = try XCTUnwrap(try ndb.lookup_note_by_key_and_copy(try XCTUnwrap(keys.first)))
        XCTAssertEqual(rumor.kind, 14)
        XCTAssertEqual(rumor.content, "the rumor made it through", "the stored rumor is plaintext")
        XCTAssertEqual(rumor.created_at, 1_700_000_000,
                       "the rumor's created_at is the real send time, not the wrap's randomized one")
        XCTAssertEqual(rumor.pubkey, sender.pubkey,
                       "nostrdb copies the sender pubkey from the seal onto the rumor")
    }

    /// The rumor is unsigned, and nostrdb repurposes its signature field. Check the flag and
    /// both halves of that field are readable through the Swift accessors, and that nothing
    /// mistakes the rumor for a verifiable note.
    func testUnwrappedRumorIsFlaggedAndCarriesTheReceiverAndWrap() throws {
        let receiver = generate_new_keypair()
        let sender = generate_new_keypair()
        let wrap = try Self.giftwrap(content: "secret", from: sender, to: receiver)

        let ndb = try Self.ingest(wrap, unwrappingWith: receiver)
        defer { ndb.close() }

        let filter = try NdbFilter(from: NostrFilter(kinds: [.private_dm]))
        let key = try XCTUnwrap(try ndb.query(filters: [filter], maxResults: 10).first)
        let rumor = try XCTUnwrap(try ndb.lookup_note_by_key_and_copy(key))

        XCTAssertTrue(rumor.is_rumor)
        XCTAssertEqual(rumor.rumor_receiver_pubkey, receiver.pubkey,
                       "the lower half of the sig field holds the pubkey that unwrapped the giftwrap")
        XCTAssertEqual(rumor.rumor_giftwrap_id, wrap.wrapId,
                       "the upper half of the sig field holds the giftwrap id")
        XCTAssertFalse(rumor.verify(), "a rumor has no signature, so it must never verify")

        // And the giftwrap itself is still an ordinary signed note that is not a rumor.
        let wrapNote = try XCTUnwrap(try ndb.lookup_note_and_copy(wrap.wrapId))
        XCTAssertFalse(wrapNote.is_rumor)
        XCTAssertNil(wrapNote.rumor_receiver_pubkey)
        XCTAssertNil(wrapNote.rumor_giftwrap_id)
        XCTAssertTrue(wrapNote.verify())
    }

    /// A rumor's plaintext is a private message and its signature field is not a signature, so
    /// the relay egress path has to refuse it. `make_nostr_push_event` is the single chokepoint
    /// every relay write funnels through, so assert there.
    func testRumorIsRefusedByTheRelayEgressPath() throws {
        let receiver = generate_new_keypair()
        let sender = generate_new_keypair()
        let wrap = try Self.giftwrap(content: "must not leave the device", from: sender, to: receiver)

        let ndb = try Self.ingest(wrap, unwrappingWith: receiver)
        defer { ndb.close() }

        let filter = try NdbFilter(from: NostrFilter(kinds: [.private_dm]))
        let key = try XCTUnwrap(try ndb.query(filters: [filter], maxResults: 10).first)
        let rumor = try XCTUnwrap(try ndb.lookup_note_by_key_and_copy(key))

        XCTAssertNil(make_nostr_push_event(ev: rumor), "a rumor must never be encoded into an EVENT frame")

        // The giftwrap it came out of is an ordinary note and still goes out fine.
        let wrapNote = try XCTUnwrap(try ndb.lookup_note_and_copy(wrap.wrapId))
        XCTAssertNotNil(make_nostr_push_event(ev: wrapNote))
    }

    /// The rumor has to go through the *normal* note write path, not a side channel — which
    /// is what makes it show up on a live `kinds: [14]` subscription that was already open
    /// when the giftwrap arrived.
    func testUnwrappedRumorIsDeliveredToALiveSubscription() async throws {
        let receiver = generate_new_keypair()
        let sender = generate_new_keypair()

        let dir = try XCTUnwrap(test_ndb_dir(), "could not create a temp directory")
        let ndb = try XCTUnwrap(Ndb(path: dir))
        defer { ndb.close() }
        XCTAssertTrue(ndb.add_key(receiver.privkey))

        let filter = try NdbFilter(from: NostrFilter(kinds: [.private_dm]))
        let stream = try ndb.subscribe(filters: [filter])

        let delivered = XCTestExpectation(description: "the rumor reaches the live subscription")
        let receivedContent = NoteBox()
        let reader = Task {
            for await item in stream {
                guard case .event(let noteKey) = item else { continue }   // skip eose
                // Read it back the way `SubscriptionManager` does: through a lender.
                let note = NdbNoteLender(ndb: ndb, noteKey: noteKey).justGetACopy()
                XCTAssertEqual(note?.is_rumor, true,
                               "a note delivered to a kinds: [14] subscription is a rumor")
                receivedContent.value = note?.content
                delivered.fulfill()
                break
            }
        }
        defer { reader.cancel() }

        let wrap = try Self.giftwrap(content: "live rumor", from: sender, to: receiver)
        XCTAssertTrue(ndb.process_events(wrap.wire))

        await fulfillment(of: [delivered], timeout: 10.0)
        XCTAssertEqual(receivedContent.value, "live rumor")
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

    /// A reference-typed slot, so the stream-reading task can hand a value back out.
    private final class NoteBox {
        var value: String?
    }

    /// A NIP-59 giftwrap and the pieces of it a test needs to assert on.
    private struct Giftwrap {
        /// The kind-1059 wrap as a relay `EVENT` line, ready for `Ndb.process_events`.
        let wire: String
        /// The wrap's id, which nostrdb stashes in the rumor's signature field.
        let wrapId: NoteId
    }

    /// Builds a real NIP-59 giftwrap around a kind-14 rumor: rumor -> kind-13 seal
    /// (NIP-44 sender -> receiver, signed by the sender) -> kind-1059 wrap (NIP-44
    /// ephemeral -> receiver, signed by the ephemeral key).
    ///
    /// Nothing here is faked: nostrdb verifies the wrap and the seal signatures and does
    /// both NIP-44 decryptions itself, so a fixture that only *looked* right would be
    /// dropped rather than unwrapped.
    ///
    /// - Parameter sentAt: the rumor's `created_at` — the real send time. The wrap gets a
    ///   deliberately different timestamp, standing in for the randomized one a real
    ///   sender would use, so tests can tell the two apart.
    private static func giftwrap(content: String,
                                 from sender: FullKeypair,
                                 to receiver: FullKeypair,
                                 sentAt: UInt32 = 1_700_000_000) throws -> Giftwrap {
        let ephemeral = generate_new_keypair()

        // The rumor. nostrdb ignores its pubkey and signature (it copies the sender pubkey
        // off the seal and recalculates the id), but signing it keeps the fixture a valid
        // note that `NostrEvent` will build for us.
        let rumor = try XCTUnwrap(NostrEvent(content: content,
                                             keypair: sender.to_keypair(),
                                             kind: 14,
                                             tags: [["p", receiver.pubkey.hex()]],
                                             createdAt: sentAt))
        let rumorJson = try XCTUnwrap(encode_json(rumor))

        // The seal: the rumor, NIP-44 encrypted to the receiver and signed by the sender.
        let sealedRumor = try NIP44v2Encryption.encrypt(plaintext: rumorJson,
                                                        privateKeyA: sender.privkey,
                                                        publicKeyB: receiver.pubkey)
        let seal = try XCTUnwrap(NostrEvent(content: sealedRumor,
                                            keypair: sender.to_keypair(),
                                            kind: 13,
                                            tags: [],
                                            createdAt: sentAt))
        let sealJson = try XCTUnwrap(encode_json(seal))

        // The wrap: the seal, NIP-44 encrypted to the receiver from a throwaway key. Its
        // created_at is offset to stand in for the randomization a real sender applies.
        let wrappedSeal = try NIP44v2Encryption.encrypt(plaintext: sealJson,
                                                        privateKeyA: ephemeral.privkey,
                                                        publicKeyB: receiver.pubkey)
        let wrap = try XCTUnwrap(NostrEvent(content: wrappedSeal,
                                            keypair: ephemeral.to_keypair(),
                                            kind: 1059,
                                            tags: [["p", receiver.pubkey.hex()]],
                                            createdAt: sentAt - 86_400))
        let wrapJson = try XCTUnwrap(encode_json(wrap))

        // `ndb_process_events` only ingests up to the last newline.
        return Giftwrap(wire: "[\"EVENT\",\"s\",\(wrapJson)]\n", wrapId: wrap.id)
    }

    /// Registers `receiver`'s key, ingests `wrap`, then hands back a freshly opened `Ndb`
    /// reading the same files.
    ///
    /// Closing the first handle is what makes this deterministic: unwrapping happens on the
    /// ingester pool and `ndb_destroy` drains it, so the reopened database is known to have
    /// the rumor in it.
    private static func ingest(_ wrap: Giftwrap, unwrappingWith receiver: FullKeypair) throws -> Ndb {
        let dir = try XCTUnwrap(test_ndb_dir(), "could not create a temp directory")

        do {
            let seed = try XCTUnwrap(Ndb(path: dir))
            XCTAssertTrue(seed.add_key(receiver.privkey), "the ingester should accept our key")
            XCTAssertTrue(seed.process_events(wrap.wire))
            seed.close()
        }

        return try XCTUnwrap(Ndb(path: dir))
    }
}
