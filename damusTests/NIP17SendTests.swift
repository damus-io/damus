//
//  NIP17SendTests.swift
//  damusTests
//
//  Created by Claude on 2026-09-03.
//

import XCTest
@testable import damus

/// Covers the NIP-17 send path: ``NIP17/createDirectMessage(_:to:keypair:createdAt:)`` and the
/// ``NIP59`` layers under it.
///
/// The load-bearing test here is ``testOurOwnWrapUnwrapsInNostrdb``. nostrdb's ingester is the exact
/// decoder our own client runs against the copy we address to ourselves, so a wrap it cannot open is
/// a message we can never read back — the outbound half of a conversation lost. Asserting the shape
/// of the JSON we produce is not enough; the wrap has to survive the real decoder.
final class NIP17SendTests: XCTestCase {

    // MARK: What goes on the wire

    /// Two wraps, one per copy, and *only* wraps: the message itself never gets published.
    func testASentMessageIsTwoGiftwrapsAndNothingElse() throws {
        let alice = generate_new_keypair()
        let bob = generate_new_keypair()

        let dm = try NIP17.createDirectMessage("hi bob", to: bob.pubkey, keypair: alice)

        XCTAssertEqual(dm.giftWraps.count, 2)
        XCTAssertEqual(dm.giftWraps.map({ $0.kind }), [1059, 1059],
                       "only the kind-1059 wraps are publishable")
        XCTAssertEqual(Set(dm.giftWraps.map({ $0.referenced_pubkeys.first })), [bob.pubkey, alice.pubkey],
                       "one wrap addressed to the recipient, one to ourselves")
        XCTAssertTrue(dm.giftWraps.contains(where: { $0.id == dm.giftWrapToSelf.id }),
                      "the copy we ingest locally has to be one of the ones we publish")
        XCTAssertEqual(dm.giftWrapToSelf.referenced_pubkeys.first, alice.pubkey)
    }

    /// The point of the ephemeral key is that a relay operator cannot tell the two wraps of one
    /// message came from the same person. Reusing the key across the pair would hand them exactly
    /// that, so the two wraps must share nothing: not the signing key, not the id.
    func testTheTwoWrapsAreNotLinkable() throws {
        let alice = generate_new_keypair()
        let bob = generate_new_keypair()

        let dm = try NIP17.createDirectMessage("unlinkable", to: bob.pubkey, keypair: alice)
        let (first, second) = (dm.giftWraps[0], dm.giftWraps[1])

        XCTAssertNotEqual(first.pubkey, second.pubkey, "each wrap gets its own throwaway signing key")
        XCTAssertNotEqual(first.pubkey, alice.pubkey, "our own pubkey must never sign a wrap")
        XCTAssertNotEqual(second.pubkey, alice.pubkey)
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertNotEqual(first.content, second.content, "each wrap encrypts its own seal")

        // And a second message reuses nothing from the first.
        let again = try NIP17.createDirectMessage("unlinkable", to: bob.pubkey, keypair: alice)
        XCTAssertTrue(Set(again.giftWraps.map({ $0.pubkey })).isDisjoint(with: Set(dm.giftWraps.map({ $0.pubkey }))))
    }

    /// Both published wraps are ordinary signed notes, so nothing on the relay egress path objects to
    /// them — the guards there exist to catch rumors, and a wrap is not one.
    func testBothWrapsAreSignedAndPublishable() throws {
        let alice = generate_new_keypair()
        let bob = generate_new_keypair()

        let dm = try NIP17.createDirectMessage("publish me", to: bob.pubkey, keypair: alice)

        for wrap in dm.giftWraps {
            XCTAssertTrue(wrap.verify(), "a wrap is signed by its ephemeral key")
            XCTAssertFalse(wrap.is_rumor)
            XCTAssertNotNil(make_nostr_push_event(ev: wrap))
        }
    }

    /// A message to ourselves needs one wrap, not two: the recipient's copy and our own copy are the
    /// same copy, and a second would publish the message twice for nothing.
    func testANoteToSelfIsASingleWrap() throws {
        let alice = generate_new_keypair()

        let dm = try NIP17.createDirectMessage("note to self", to: alice.pubkey, keypair: alice)

        XCTAssertEqual(dm.giftWraps.count, 1)
        XCTAssertEqual(dm.giftWrapToSelf.id, dm.giftWraps[0].id)
        XCTAssertEqual(dm.giftWraps[0].referenced_pubkeys.first, alice.pubkey)
    }

    // MARK: Timestamps

    /// The rumor keeps the real send time — it is inside two layers of encryption, so nobody but the
    /// two parties ever sees it, and it is what conversations are ordered by. The seal and the wrap
    /// get randomized ones, because those *are* public.
    func testOnlyTheRumorCarriesTheRealSendTime() throws {
        let alice = generate_new_keypair()
        let bob = generate_new_keypair()
        let sentAt: UInt32 = 1_900_000_000

        let dm = try NIP17.createDirectMessage("when?", to: bob.pubkey, keypair: alice, createdAt: sentAt)

        XCTAssertEqual(dm.rumor.created_at, sentAt)
        for wrap in dm.giftWraps {
            XCTAssertLessThanOrEqual(wrap.created_at, UInt32(Date().timeIntervalSince1970),
                                     "fuzzing only ever moves a timestamp into the past — a future one is rejected by relays")
        }
    }

    /// The fuzz window has to be the same two days the inbound giftwrap subscription widens its
    /// `since` bound by, or the two halves of the epic disagree about how far a wrap can drift.
    func testFuzzedTimestampsStayInsideTheWindowWeSubscribeWith() {
        let now: UInt32 = 1_900_000_000
        let window = NostrKind.giftwrapCreatedAtFuzzWindow

        for _ in 0..<500 {
            let fuzzed = NIP59.fuzzedTimestamp(now: now)
            XCTAssertLessThanOrEqual(fuzzed, now)
            XCTAssertGreaterThanOrEqual(fuzzed, now - window)
        }
    }

    /// A device whose clock has not been set yet reports a `now` of a few seconds past the epoch, and
    /// subtracting a two-day offset from that would trap on unsigned underflow rather than send a
    /// message. Clamp instead.
    func testFuzzedTimestampDoesNotUnderflowOnAnUnsetClock() {
        for now in UInt32(0)...UInt32(3) {
            XCTAssertEqual(NIP59.fuzzedTimestamp(now: now), 0)
        }
    }

    // MARK: The layers, per NIP-59

    /// Peels our own wrap by hand and checks each layer against the spec, since a receiver that is
    /// not us will do exactly this: decrypt the wrap with their key and the wrap's ephemeral pubkey,
    /// check the seal's signature, decrypt the seal with their key and the *sender's* pubkey.
    func testTheThreeLayersMatchTheSpec() throws {
        let alice = generate_new_keypair()
        let bob = generate_new_keypair()
        let sentAt: UInt32 = 1_900_000_000

        let dm = try NIP17.createDirectMessage("layer check", to: bob.pubkey, keypair: alice, createdAt: sentAt)
        let wrapToBob = try XCTUnwrap(dm.giftWraps.first(where: { $0.referenced_pubkeys.first == bob.pubkey }))

        // Layer 3 -> 2: the wrap is encrypted to Bob from the ephemeral key that signed it.
        let sealJson = try NIP44v2Encryption.decrypt(payload: wrapToBob.content,
                                                     privateKeyA: bob.privkey,
                                                     publicKeyB: wrapToBob.pubkey)
        let seal = try XCTUnwrap(NostrEvent.owned_from_json(json: sealJson))
        XCTAssertEqual(seal.kind, 13)
        XCTAssertEqual(seal.pubkey, alice.pubkey, "the seal is the only layer that names the sender")
        XCTAssertTrue(seal.verify(), "and it is signed by them, which is what proves authorship")
        XCTAssertEqual(seal.tags.count, 0, "a seal carries no tags: one would leak in the clear")

        // Layer 2 -> 1: the seal is encrypted to Bob by Alice.
        let rumorJson = try NIP44v2Encryption.decrypt(payload: seal.content,
                                                      privateKeyA: bob.privkey,
                                                      publicKeyB: alice.pubkey)
        let rumor = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(rumorJson.utf8)) as? [String: Any])
        XCTAssertNil(rumor["sig"], "a rumor is unsigned by construction — that is what makes it a rumor")
        XCTAssertEqual((rumor["kind"] as? NSNumber)?.uint32Value, 14)
        XCTAssertEqual(rumor["content"] as? String, "layer check")
        XCTAssertEqual((rumor["created_at"] as? NSNumber)?.uint32Value, sentAt)
        XCTAssertEqual(rumor["pubkey"] as? String, alice.pubkey.hex())
        XCTAssertEqual(rumor["id"] as? String, dm.rumor.id.hex())
        XCTAssertEqual(rumor["tags"] as? [[String]], [["p", bob.pubkey.hex()]],
                       "1:1 only: a single p tag, because our read path drops group rumors")
    }

    /// The rumor's id is the ordinary NIP-01 event id. It has to be, because nostrdb recomputes it
    /// from the same fields when it stores the rumor, and a disagreement would mean our optimistic
    /// copy of a sent message and the copy that comes back never dedupe.
    func testTheRumorIdIsTheOrdinaryEventId() throws {
        let alice = generate_new_keypair()
        let bob = generate_new_keypair()

        let dm = try NIP17.createDirectMessage("id check", to: bob.pubkey, keypair: alice, createdAt: 1_900_000_000)

        XCTAssertEqual(dm.rumor.id,
                       calculate_event_id(pubkey: alice.pubkey,
                                          created_at: 1_900_000_000,
                                          kind: 14,
                                          tags: [["p", bob.pubkey.hex()]],
                                          content: "id check"))
    }

    // MARK: Round-tripping through nostrdb, the decoder we actually read with

    /// The copy we address to ourselves is the only copy of our own sent message we can ever open, and
    /// nostrdb's ingester is what opens it. Hand it the wrap the way `DMChatView` does — through
    /// `Ndb.add(event:)` — and check the plaintext rumor comes back out of a `kinds: [14]` query.
    func testOurOwnWrapUnwrapsInNostrdb() throws {
        let alice = generate_new_keypair()
        let bob = generate_new_keypair()
        let sentAt: UInt32 = 1_900_000_000

        let dm = try NIP17.createDirectMessage("does our own reader open this?",
                                               to: bob.pubkey, keypair: alice, createdAt: sentAt)

        let ndb = try Self.ingest(dm.giftWrapToSelf, unwrappingWith: alice)
        defer { ndb.close() }

        let rumor = try XCTUnwrap(Self.onlyRumor(in: ndb), "our own wrap must be unwrappable by our own key")
        XCTAssertEqual(rumor.kind, 14)
        XCTAssertEqual(rumor.content, "does our own reader open this?", "and the rumor inside is plaintext")
        XCTAssertEqual(rumor.created_at, sentAt, "with the real send time, not either fuzzed one")
        XCTAssertEqual(rumor.pubkey, alice.pubkey)
        XCTAssertEqual(rumor.referenced_pubkeys.first, bob.pubkey)
        XCTAssertEqual(rumor.id, dm.rumor.id,
                       "the id nostrdb recomputes matches the one we put in the rumor JSON")
        XCTAssertTrue(rumor.is_rumor, "so `HomeModel.handle_private_dm`'s rumor guard lets it through")
        XCTAssertEqual(rumor.rumor_giftwrap_id, dm.giftWrapToSelf.id)
        XCTAssertEqual(rumor.rumor_receiver_pubkey, alice.pubkey)
    }

    /// The recipient's copy has to open with the recipient's key — the same unwrap, from their side.
    func testTheRecipientsWrapUnwrapsWithTheirKey() throws {
        let alice = generate_new_keypair()
        let bob = generate_new_keypair()

        let dm = try NIP17.createDirectMessage("hi bob", to: bob.pubkey, keypair: alice, createdAt: 1_900_000_000)
        let wrapToBob = try XCTUnwrap(dm.giftWraps.first(where: { $0.referenced_pubkeys.first == bob.pubkey }))

        let ndb = try Self.ingest(wrapToBob, unwrappingWith: bob)
        defer { ndb.close() }

        let rumor = try XCTUnwrap(Self.onlyRumor(in: ndb))
        XCTAssertEqual(rumor.content, "hi bob")
        XCTAssertEqual(rumor.pubkey, alice.pubkey, "Bob learns who sent it from the seal, nowhere else")
        XCTAssertEqual(rumor.rumor_receiver_pubkey, bob.pubkey)
    }

    /// Nothing but the addressee can open a wrap. Ingesting the recipient's copy with *our* key must
    /// leave it sitting there unwrapped, which is why `DMChatView` ingests only the self-addressed one.
    func testTheRecipientsWrapDoesNotUnwrapWithOurKey() throws {
        let alice = generate_new_keypair()
        let bob = generate_new_keypair()

        let dm = try NIP17.createDirectMessage("not for us", to: bob.pubkey, keypair: alice)
        let wrapToBob = try XCTUnwrap(dm.giftWraps.first(where: { $0.referenced_pubkeys.first == bob.pubkey }))

        let ndb = try Self.ingest(wrapToBob, unwrappingWith: alice)
        defer { ndb.close() }

        XCTAssertNil(Self.onlyRumor(in: ndb),
                     "a wrap addressed to someone else yields no rumor, so ingesting one would only leave un-openable junk behind")
    }

    /// The rumor nostrdb hands back is plaintext with a signature field that is not a signature, so
    /// the relay egress path has to keep refusing it even though we are the ones who created it.
    func testTheUnwrappedRumorStillCannotBeSent() throws {
        let alice = generate_new_keypair()
        let bob = generate_new_keypair()

        let dm = try NIP17.createDirectMessage("must not leave the device", to: bob.pubkey, keypair: alice)
        let ndb = try Self.ingest(dm.giftWrapToSelf, unwrappingWith: alice)
        defer { ndb.close() }

        let rumor = try XCTUnwrap(Self.onlyRumor(in: ndb))
        XCTAssertFalse(rumor.verify())
        XCTAssertNil(make_nostr_push_event(ev: rumor))
    }

    /// Why ``NIP59/Rumor`` is not a ``NostrEvent``.
    ///
    /// The relay egress guards test ``NdbNote/is_rumor``, which is nostrdb's `NDB_NOTE_FLAG_RUMOR` —
    /// a flag only nostrdb's unwrapper ever sets. A kind-14 built locally in Swift does not carry it,
    /// so both guards wave it through, as this shows. The reason a locally-built rumor cannot reach a
    /// relay is therefore not those guards but the fact that it is not a `NostrEvent` at all and so
    /// cannot be passed to them. If this test ever starts failing because the guards learned to catch
    /// a plaintext kind 14 on its own merits, the type could safely be relaxed.
    func testTheRumorGuardsDoNotCatchALocallyBuiltKind14() throws {
        let alice = generate_new_keypair()
        let bob = generate_new_keypair()

        let localKind14 = try XCTUnwrap(NostrEvent(content: "plaintext, signed, and sendable",
                                                   keypair: alice.to_keypair(),
                                                   kind: 14,
                                                   tags: [["p", bob.pubkey.hex()]]))

        XCTAssertFalse(localKind14.is_rumor, "the rumor flag is written by nostrdb, never by us")
        XCTAssertNotNil(make_nostr_push_event(ev: localKind14),
                        "so the egress guard does not stop it — which is why `NIP59.Rumor` is not a `NostrEvent`")
    }

    // MARK: Send -> unwrap -> DM list, in one process

    /// The whole loop a sent message travels: build it, ingest our own wrap, let nostrdb unwrap it,
    /// read the rumor back with the query the DM list uses, and route it into the model with the same
    /// function `HomeModel` routes inbound rumors through.
    ///
    /// This is what makes the send path trustworthy end to end without a relay or a simulator: it is
    /// the same code from `NIP17.createDirectMessage` all the way to `DirectMessagesModel`, with only
    /// `HomeModel`'s subscription plumbing standing in as a direct call.
    func testASentMessageComesBackAsAConversationWithTheRecipient() throws {
        let alice = generate_new_keypair()
        let bob = generate_new_keypair()

        let dm = try NIP17.createDirectMessage("round trip", to: bob.pubkey, keypair: alice, createdAt: 1_900_000_000)
        let ndb = try Self.ingest(dm.giftWrapToSelf, unwrappingWith: alice)
        defer { ndb.close() }
        let rumor = try XCTUnwrap(Self.onlyRumor(in: ndb))

        let model = DirectMessagesModel(our_pubkey: alice.pubkey)
        handle_incoming_dms(prev_events: NewEventsBits(), dms: model, our_pubkey: alice.pubkey, evs: [rumor])

        XCTAssertEqual(model.dms.count, 1)
        XCTAssertEqual(model.dms.first?.pubkey, bob.pubkey,
                       "a message we sent is keyed on who we sent it to, not on us")
        XCTAssertEqual(model.dms.first?.events.map({ $0.content }), ["round trip"])
    }

    /// And the copy that eventually comes back from a relay is the same note, so it dedupes rather
    /// than showing the message twice.
    func testTheRelayEchoOfOurOwnWrapDoesNotDuplicateTheMessage() throws {
        let alice = generate_new_keypair()
        let bob = generate_new_keypair()

        let dm = try NIP17.createDirectMessage("only once", to: bob.pubkey, keypair: alice, createdAt: 1_900_000_000)
        let ndb = try Self.ingest(dm.giftWrapToSelf, unwrappingWith: alice)
        defer { ndb.close() }
        let rumor = try XCTUnwrap(Self.onlyRumor(in: ndb))

        let model = DirectMessagesModel(our_pubkey: alice.pubkey)
        // The local ingest, then the same wrap arriving again off the wire.
        handle_incoming_dms(prev_events: NewEventsBits(), dms: model, our_pubkey: alice.pubkey, evs: [rumor, rumor])

        XCTAssertEqual(model.dms.count, 1)
        XCTAssertEqual(model.dms.first?.events.count, 1)
    }

    // MARK: Helpers

    /// Registers `receiver`'s key, hands `wrap` to the database the way `DMChatView` does, then
    /// reopens it.
    ///
    /// Closing the first handle is what makes this deterministic: unwrapping happens on the ingester
    /// pool and `ndb_destroy` drains it, so the reopened database is known to have finished.
    private static func ingest(_ wrap: NostrEvent, unwrappingWith receiver: FullKeypair) throws -> Ndb {
        let dir = try XCTUnwrap(test_ndb_dir(), "could not create a temp directory")

        do {
            let seed = try XCTUnwrap(Ndb(path: dir))
            XCTAssertTrue(seed.add_key(receiver.privkey), "the ingester should accept our key")
            try seed.add(event: wrap)
            seed.close()
        }

        return try XCTUnwrap(Ndb(path: dir))
    }

    /// The single kind-14 rumor in `ndb`, read back with the query the DM models use, or `nil` if the
    /// unwrap produced none.
    private static func onlyRumor(in ndb: Ndb) -> NostrEvent? {
        guard let filter = try? NdbFilter(from: NostrFilter(kinds: [.private_dm])),
              let keys = try? ndb.query(filters: [filter], maxResults: 10),
              keys.count == 1,
              let key = keys.first
        else { return nil }

        return try? ndb.lookup_note_by_key_and_copy(key)
    }
}
