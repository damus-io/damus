//
//  DMTypingIndicatorTests.swift
//  damusTests
//
//  Created by Clawdbot on 2026-01-25.
//

import XCTest
@testable import damus

final class DMTypingIndicatorTests: XCTestCase {

    private var alice: Keypair {
        let sec = hex_decode_privkey("494c680d20f202807a116a6915815bd76a27d62802e7585806f6a2e034cb5cdb")!
        let pk = hex_decode_pubkey("22d925632551a3299022e98de7f9c1087f79a21209f3413ec24ec219b08bd1e4")!
        return Keypair(pubkey: pk, privkey: sec)
    }

    private var bob: Keypair {
        let sec = hex_decode_privkey("aa8920b05b4bd5c79fce46868ed5ebc82bdb91b211850b14541bfbd13953cfef")!
        let pk = hex_decode_pubkey("5a9a277dca94260688ecf7d63053de8c121b7f01f609d7f84a1eb9cff64e4606")!
        return Keypair(pubkey: pk, privkey: sec)
    }

    func testTypingIndicatorEventCreationAndDecryption() throws {
        // Bob sends typing start to Alice
        guard let ev = DMTypingIndicator.makeEvent(action: .start, to: alice.pubkey, keypair: bob) else {
            XCTFail("Failed to create typing indicator event")
            return
        }

        XCTAssertEqual(ev.kind, NostrKind.typing.rawValue)

        // Ensure tags include p + namespace
        XCTAssertTrue(ev.tags.contains(where: { $0.count >= 2 && $0[0] == "p" && $0[1] == alice.pubkey.hex() }))
        XCTAssertTrue(ev.tags.contains(where: { $0.count >= 2 && $0[0] == "t" && $0[1] == DMTypingIndicator.namespaceTagValue }))
        XCTAssertTrue(ev.tags.contains(where: { $0.count >= 2 && $0[0] == "expiration" }))

        // Alice can decrypt and see "start"
        let decrypted = try NIP04.decryptContent(
            recipientPrivateKey: try XCTUnwrap(alice.privkey),
            senderPubkey: bob.pubkey,
            content: ev.content,
            encoding: .base64
        )
        XCTAssertEqual(decrypted, "start")
    }

    @MainActor
    func testDirectMessageModelTypingAutoClear() async {
        let model = DirectMessageModel(our_pubkey: alice.pubkey, pubkey: bob.pubkey)
        XCTAssertFalse(model.partner_is_typing)

        model.set_partner_typing(true, autoClearAfter: 0.05)
        XCTAssertTrue(model.partner_is_typing)

        try? await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertFalse(model.partner_is_typing)
    }
}
