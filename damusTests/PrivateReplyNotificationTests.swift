//
//  PrivateReplyNotificationTests.swift
//  damusTests
//
//  Created by Claude on 2026-09-05.
//

import XCTest
@testable import damus

/// Covers the notification an inbound private reply produces — `generate_local_notification_object`,
/// which both the in-app path (`HomeModel`) and the push extension (`NotificationService`) go
/// through, so one branch covers both.
///
/// The claim under test is a pair. A private reply must *not* be announced the way a public reply
/// is, with a public-sounding title and its plaintext under the reply/mention settings; and a public
/// mention must be announced exactly as it is today. Both matter because the branch is on
/// ``NdbNote/is_private_reply`` — a predicate — rather than on the kind, and a predicate that is
/// wrong in either direction is a bug you would only find on a lock screen.
final class PrivateReplyNotificationTests: XCTestCase {

    // MARK: The type

    /// ``LocalNotificationType/from(note:)`` is what the tap-routing path uses to recover the type
    /// from a pushed note, and it has to see past the kind. A signed kind 1 and a rumor kind 1 are
    /// the same kind and different notifications.
    @MainActor
    func testTheTypeIsReadFromTheNoteAndNotTheKind() throws {
        let alice = generate_new_keypair()
        let bob = generate_new_keypair()
        let (rumor, _) = try inboundPrivateReply(from: bob, to: alice)
        let publicNote = try XCTUnwrap(NostrEvent(content: "hello", keypair: bob.to_keypair(), kind: 1, tags: []))

        XCTAssertEqual(LocalNotificationType.from(note: rumor), .private_reply)
        XCTAssertEqual(LocalNotificationType.from(note: publicNote), .mention,
                       "a signed kind 1 is a mention, as it has always been")
    }

    // MARK: What we announce

    /// An inbound private reply notifies as one: its own type, and the plaintext as the body — the
    /// same trade a NIP-17 DM already makes.
    @MainActor
    func testAnInboundPrivateReplyNotifiesAsPrivate() throws {
        let alice = test_keypair_full
        let bob = generate_new_keypair()
        let (rumor, state) = try inboundPrivateReply(from: bob, to: alice)
        state.settings.dm_notification = true

        let notification = try XCTUnwrap(generate_local_notification_object(ndb: state.ndb, from: rumor, state: state))

        XCTAssertEqual(notification.type, .private_reply)
        XCTAssertEqual(notification.content, "between us", "the body is the reply, as a DM's is")
        XCTAssertEqual(notification.target.id, rumor.id, "tapping it opens the reply, in the thread it answers")
    }

    /// Gated on the DM setting, not on the reply/mention settings. Somebody who turned off DM
    /// notifications has said they do not want private messages on their lock screen, and this is one;
    /// somebody who left mention notifications on said that about public notes, at a time when no note
    /// could be private.
    @MainActor
    func testTheDmSettingGatesItAndTheMentionSettingDoesNot() throws {
        let alice = test_keypair_full
        let bob = generate_new_keypair()
        let (rumor, state) = try inboundPrivateReply(from: bob, to: alice)

        state.settings.dm_notification = false
        state.settings.mention_notification = true
        XCTAssertNil(generate_local_notification_object(ndb: state.ndb, from: rumor, state: state),
                     "the mention setting must not let a private reply through the gate the DM setting closed")

        state.settings.dm_notification = true
        state.settings.mention_notification = false
        XCTAssertNotNil(generate_local_notification_object(ndb: state.ndb, from: rumor, state: state),
                        "and it must not hold one back either")
    }

    /// Our own sent reply comes back through the same ingester as an inbound one — that self-addressed
    /// wrap is the only copy we can read. It must not notify us about ourselves.
    @MainActor
    func testOurOwnSentPrivateReplyDoesNotNotifyUs() throws {
        let alice = test_keypair_full
        let bob = generate_new_keypair()
        let (rumor, state) = try ourOwnPrivateReply(from: alice, to: bob)
        state.settings.dm_notification = true

        XCTAssertEqual(rumor.pubkey, alice.pubkey)
        XCTAssertNil(generate_local_notification_object(ndb: state.ndb, from: rumor, state: state))
    }

    // MARK: What must not change

    /// The public path, asserted because the branch is a predicate rather than a kind: get it wrong
    /// and every ordinary mention starts announcing itself as private.
    @MainActor
    func testAPublicMentionNotifiesExactlyAsBefore() throws {
        let alice = test_keypair_full
        let bob = generate_new_keypair()
        let state = make_test_damus_state()
        state.settings.mention_notification = true
        state.settings.dm_notification = false

        // A reply to a note of ours, which is what `generate_text_mention_notification` looks for.
        let ours = try XCTUnwrap(NostrEvent(content: "our public note", keypair: alice.to_keypair(), kind: 1, tags: []))
        try state.ndb.add(event: ours)
        try poll(until: { (try? state.ndb.lookup_note_and_copy(ours.id)) != nil })
        let reply = try XCTUnwrap(NostrEvent(content: "a public reply", keypair: bob.to_keypair(), kind: 1,
                                             tags: nip10_reply_tags(replying_to: ours, keypair: bob.to_keypair(), relayURL: nil)))

        let notification = try XCTUnwrap(generate_local_notification_object(ndb: state.ndb, from: reply, state: state))

        XCTAssertEqual(notification.type, .reply, "still a reply, with the DM setting off")
        XCTAssertFalse(reply.is_private_reply)
    }

    // MARK: The lock screen

    /// A private reply and a public reply carry the same shape of body — the reply's text — so the
    /// whole difference a reader gets is the title. It has to actually differ.
    @MainActor
    func testThePrivateReplyTitleIsNotTheReplyTitle() throws {
        let alice = generate_new_keypair()
        let bob = generate_new_keypair()
        let (rumor, _) = try inboundPrivateReply(from: bob, to: alice)

        let private_reply = LocalNotification(type: .private_reply, event: rumor, target: .note(rumor), content: rumor.content)
        let public_reply = LocalNotification(type: .reply, event: rumor, target: .note(rumor), content: rumor.content)

        let formatted = try XCTUnwrap(NotificationFormatter.shared.format_message(displayName: "bob", notify: private_reply))
        let public_formatted = try XCTUnwrap(NotificationFormatter.shared.format_message(displayName: "bob", notify: public_reply))

        XCTAssertNotEqual(formatted.content.title, public_formatted.content.title)
        XCTAssertNotEqual(formatted.identifier, public_formatted.identifier,
                          "and they group separately in Notification Centre")
        XCTAssertEqual(formatted.content.body, rumor.content)
    }

    // MARK: Helpers

    /// A private reply `sender` sent to a public note by `receiver`, read back as `receiver` out of a
    /// `DamusState` on its own database — the only way to get a note whose rumor flag is genuine.
    @MainActor
    private func inboundPrivateReply(from sender: FullKeypair, to receiver: FullKeypair) throws -> (NostrEvent, DamusState) {
        return try ingestedPrivateReply(from: sender, toANoteBy: receiver, readAs: receiver)
    }

    /// A private reply *we* sent, read back out of our own self-addressed wrap.
    @MainActor
    private func ourOwnPrivateReply(from us: FullKeypair, to them: FullKeypair) throws -> (NostrEvent, DamusState) {
        return try ingestedPrivateReply(from: us, toANoteBy: them, readAs: us)
    }

    @MainActor
    private func ingestedPrivateReply(from sender: FullKeypair, toANoteBy receiver: FullKeypair, readAs reader: FullKeypair) throws -> (NostrEvent, DamusState) {
        let state = make_test_damus_state(keypair: reader.to_keypair())
        XCTAssertTrue(state.ndb.add_key(reader.privkey), "the ingester needs the reader's key to unwrap")

        let parent = try XCTUnwrap(NostrEvent(content: "a public note", keypair: receiver.to_keypair(), kind: 1, tags: []))
        let tags = nip10_reply_tags(replying_to: parent, keypair: sender.to_keypair(), relayURL: nil)
        let built = try NIP59.createPrivateReply(NostrPost(content: "between us", tags: tags),
                                                 replyingTo: parent,
                                                 keypair: sender)
        let wrap = reader.pubkey == sender.pubkey ? built.giftWrapToSelf : try XCTUnwrap(built.giftWrapToReceiver)
        try state.ndb.add(event: wrap)

        var found: NdbNote? = nil
        let filter = try NdbFilter(from: NostrFilter(kinds: [.text]))
        try poll(until: {
            guard let key = try state.ndb.query(filters: [filter], maxResults: 10).first else { return false }
            found = try state.ndb.lookup_note_by_key_and_copy(key)
            return found != nil
        })
        let rumor = try XCTUnwrap(found)
        XCTAssertTrue(rumor.is_private_reply, "fixture is only meaningful if nostrdb flagged it")
        return (rumor, state)
    }

    private func poll(until condition: () throws -> Bool) throws {
        for _ in 0..<200 {
            if try condition() { return }
            usleep(25_000)
        }
        XCTFail("timed out waiting for nostrdb")
    }
}
