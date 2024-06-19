//
//  NIP10Tests.swift
//  damusTests
//
//  Created by William Casarin on 2024-04-25.
//

import XCTest
@testable import damus

final class NIP10Tests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testExample() throws {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
        // Any test you write for XCTest can be annotated as throws and async.
        // Mark your test throws to produce an unexpected failure when your test encounters an uncaught error.
        // Mark your test async to allow awaiting for asynchronous code to complete. Check the results with assertions afterwards.
    }

    func test_root_with_mention_nip10() {
        let root_id_hex = "a32d70d331f4bea7a859ac71d85a9b4e0c2d1fa9aaf7237a17f85a6227f52fdb"
        let root_id = NoteId(hex: root_id_hex)!
        let mention_hex = "e47b7e156acec6881c89a53f1a9e349a982024245e2c398f8a5b4973b7a89ab3"
        let mention_id = NoteId(hex: mention_hex)!

        let tags =
            [["e", root_id_hex,"","root"],
             ["e", mention_hex,"","mention"],
             ["p","c4eabae1be3cf657bc1855ee05e69de9f059cb7a059227168b80b89761cbc4e0"],
             ["p","604e96e099936a104883958b040b47672e0f048c98ac793f37ffe4c720279eb2"],
             ["p","ffd375eb40eb486656a028edbc83825f58ff0d5c4a1ba22fe7745d284529ed08","","mention"],
             ["q","e47b7e156acec6881c89a53f1a9e349a982024245e2c398f8a5b4973b7a89ab3"]
            ]

        let note = NdbNote(content: "hi", keypair: test_keypair, kind: 1, tags: tags)!
        let thread = ThreadReply(tags: note.tags)

        XCTAssertNotNil(thread)
        guard let thread else { return }

        XCTAssertEqual(thread.root.note_id, root_id)
        XCTAssertEqual(thread.reply.note_id, root_id)
        XCTAssertEqual(thread.mention?.ref.note_id, mention_id)
    }

    func test_new_nip10() {
        let root_note_id_hex = "7c7d37bc8c04d2ec65cbc7d9275253e6b5cc34b5d10439f158194a3feefa8d52"
        let direct_reply_hex = "7c7d37bc8c04d2ec65cbc7d9275253e6b5cc34b5d10439f158194a3feefa8d51"
        let reply_hex = "7c7d37bc8c04d2ec65cbc7d9275253e6b5cc34b5d10439f158194a3feefa8d53"
        let mention_hex = "7c7d37bc8c04d2ec65cbc7d9275253e6b5cc34b5d10439f158194a3feefa8d54"

        let tags = [
            ["e", mention_hex, "", "mention"],
            ["e", direct_reply_hex, "", "reply"],
            ["e", root_note_id_hex, "", "root"],
            ["e", reply_hex, "", "reply"],
        ]

        let root_note_id = NoteId(hex: root_note_id_hex)!
        let reply_id = NoteId(hex: reply_hex)!
        let mention_id = NoteId(hex: mention_hex)!

        let note = NdbNote(content: "hi", keypair: test_keypair, kind: 1, tags: tags)!
        let tr = interp_event_refs_without_mentions_ndb(note.referenced_noterefs)

        XCTAssertEqual(tr?.root.note_id, root_note_id)
        XCTAssertEqual(tr?.reply.note_id, reply_id)
        XCTAssertEqual(tr?.mention?.ref.note_id, mention_id)
    }

    func test_repost_root() {
        let mention_hex = "7c7d37bc8c04d2ec65cbc7d9275253e6b5cc34b5d10439f158194a3feefa8d52"
        let tags = [
            ["e", mention_hex, "", "mention"],
        ]

        let mention_id = NoteId(hex: mention_hex)!
        let note = NdbNote(content: "hi", keypair: test_keypair, kind: 1, tags: tags)!
        let tr = note.thread_reply()

        XCTAssertNil(tr)
    }
    
    func test_direct_reply_old_nip10() {
        let root_note_id_hex = "7c7d37bc8c04d2ec65cbc7d9275253e6b5cc34b5d10439f158194a3feefa8d52"
        let tags = [
            ["e", root_note_id_hex],
        ]

        let root_note_id = NoteId(hex: root_note_id_hex)!

        let note = NdbNote(content: "hi", keypair: test_keypair, kind: 1, tags: tags)!
        let tr = note.thread_reply()

        XCTAssertNotNil(tr)
        guard let tr else { return }

        XCTAssertEqual(tr.root.note_id, root_note_id)
        XCTAssertEqual(tr.reply.note_id, root_note_id)
        XCTAssertEqual(tr.is_reply_to_root, true)
    }

    func test_direct_reply_new_nip10() {
        let root_note_id_hex = "7c7d37bc8c04d2ec65cbc7d9275253e6b5cc34b5d10439f158194a3feefa8d52"
        let tags = [
            ["e", root_note_id_hex, "", "root"],
        ]

        let root_note_id = NoteId(hex: root_note_id_hex)!

        let note = NdbNote(content: "hi", keypair: test_keypair, kind: 1, tags: tags)!
        let tr = note.thread_reply()
        XCTAssertNotNil(tr)
        guard let tr else { return }

        XCTAssertEqual(tr.root.note_id, root_note_id)
        XCTAssertEqual(tr.reply.note_id, root_note_id)
        XCTAssertNil(tr.mention)
        XCTAssertEqual(tr.is_reply_to_root, true)
    }
    
    // seen in the wild by the gleasonator
    func test_single_marker() {
        let root_note_id_hex = "7c7d37bc8c04d2ec65cbc7d9275253e6b5cc34b5d10439f158194a3feefa8d52"
        let tags = [
            ["e", root_note_id_hex, "", "reply"],
        ]
        
        let root_note_id = NoteId(hex: root_note_id_hex)!
        let note = NdbNote(content: "hi", keypair: test_keypair, kind: 1, tags: tags)!
        let tr = note.thread_reply()
        XCTAssertNotNil(tr)
        guard let tr else { return }

        XCTAssertNil(tr.mention)
        XCTAssertEqual(tr.root.note_id, root_note_id)
        XCTAssertEqual(tr.reply.note_id, root_note_id)
        XCTAssertEqual(tr.is_reply_to_root, true)
    }

    func test_marker_reply() {
        let note_json = """
        {
          "pubkey": "5b0183ab6c3e322bf4d41c6b3aef98562a144847b7499543727c5539a114563e",
          "content": "Can’t zap you btw",
          "id": "a8dc8b74852d7ad114d5d650b2125459c0cba3c1fdcaaf527e03f24082e11ab3",
          "created_at": 1715275773,
          "sig": "4ee5d8f954c6c087ce51ad02d30dd226eea939cd9ef4e8a8ce4bfaf3aba0a852316cfda83ce3fc9a3d98392a738e7c6b036a3b2aced1392db1be3ca190835a17",
          "kind": 1,
          "tags": [
            [
              "e",
              "1bb940ce0ba0d4a3b2a589355d908498dcd7452f941cf520072218f7e6ede75e",
              "wss://relay.nostrplebs.com",
              "reply"
            ],
            [
              "p",
              "6e75f7972397ca3295e0f4ca0fbc6eb9cc79be85bafdd56bd378220ca8eee74e"
            ],
            [
              "e",
              "00152d2945459fb394fed2ea95af879c903c4ec42d96327a739fa27c023f20e0",
              "wss://nostr.mutinywallet.com/",
              "root"
            ]
          ]
        }
        """;

        let replying_to_hex = "a8dc8b74852d7ad114d5d650b2125459c0cba3c1fdcaaf527e03f24082e11ab3"
        let pk = Pubkey(hex: "5b0183ab6c3e322bf4d41c6b3aef98562a144847b7499543727c5539a114563e")!
        //let last_reply_hex = "1bb940ce0ba0d4a3b2a589355d908498dcd7452f941cf520072218f7e6ede75e"
        let note = decode_nostr_event_json(json: note_json)!
        let reply = build_post(state: test_damus_state, post: .init(string: "hello"), action: .replying_to(note), uploadedMedias: [], pubkeys: [pk] + note.referenced_pubkeys.map({pk in pk}))
        let root_hex = "00152d2945459fb394fed2ea95af879c903c4ec42d96327a739fa27c023f20e0"

        XCTAssertEqual(reply.tags,
            [
                ["e", root_hex, "wss://nostr.mutinywallet.com/", "root"],
                ["e", replying_to_hex, "", "reply"],
                ["p", "5b0183ab6c3e322bf4d41c6b3aef98562a144847b7499543727c5539a114563e"],
                ["p", "6e75f7972397ca3295e0f4ca0fbc6eb9cc79be85bafdd56bd378220ca8eee74e"],
            ])
    }

    func test_mixed_nip10() {

        let root_note_id_hex = "27e71cf53299dafb5dc7bcc0a078357418a4375cb1097bf5184662493f79a627"
        let reply_hex = "1a616998552cf76e9786f76ac68f6104cdae46377330735c68bfe0b9426d2fa8"

        let tags = [
            [ "e", root_note_id_hex, "", "root" ],
            [ "e", "f99046bd87be7508d55e139de48517c06ef90830d77a5d3213df858d77bb2f8f" ],
            [ "e", reply_hex, "", "reply" ],
            [ "p", "3efdaebb1d8923ebd99c9e7ace3b4194ab45512e2be79c1b7d68d9243e0d2681" ],
            [ "p", "8ea485266b2285463b13bf835907161c22bb3da1e652b443db14f9cee6720a43" ],
            [ "p", "32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245" ]
        ]
        

        let root_note_id = NoteId(hex: root_note_id_hex)!
        let reply_id = NoteId(hex: reply_hex)!

        let note = NdbNote(content: "hi", keypair: test_keypair, kind: 1, tags: tags)!
        let tr = note.thread_reply()
        XCTAssertNotNil(tr)
        guard let tr else { return }

        XCTAssertEqual(tr.root.note_id, root_note_id)
        XCTAssertEqual(tr.reply.note_id, reply_id)
        XCTAssertEqual(tr.is_reply_to_root, false)
    }

    func test_deprecated_nip10() {
        let root_note_id_hex = "7c7d37bc8c04d2ec65cbc7d9275253e6b5cc34b5d10439f158194a3feefa8d52"
        let direct_reply_hex = "7c7d37bc8c04d2ec65cbc7d9275253e6b5cc34b5d10439f158194a3feefa8d51"
        let reply_hex = "7c7d37bc8c04d2ec65cbc7d9275253e6b5cc34b5d10439f158194a3feefa8d53"
        let tags = [
            ["e", root_note_id_hex],
            ["e", direct_reply_hex],
            ["e", reply_hex],
        ]

        let root_note_id = NoteId(hex: root_note_id_hex)!
        let direct_reply_id = NoteId(hex: direct_reply_hex)!
        let reply_id = NoteId(hex: reply_hex)!

        let note = NdbNote(content: "hi", keypair: test_keypair, kind: 1, tags: tags)!
        let tr = note.thread_reply()
        XCTAssertNotNil(tr)
        guard let tr else { return }

        XCTAssertEqual(tr.root.note_id, root_note_id)
        XCTAssertEqual(tr.reply.note_id, reply_id)
        XCTAssertEqual(tr.is_reply_to_root, false)
    }



    func testPerformanceExample() throws {
        // This is an example of a performance test case.
        self.measure {
            // Put the code you want to measure the time of here.
        }
    }

}
