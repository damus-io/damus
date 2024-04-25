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

    func test_new_nip10() {
        let root_note_id_hex = "7c7d37bc8c04d2ec65cbc7d9275253e6b5cc34b5d10439f158194a3feefa8d52"
        let direct_reply_hex = "7c7d37bc8c04d2ec65cbc7d9275253e6b5cc34b5d10439f158194a3feefa8d51"
        let reply_hex = "7c7d37bc8c04d2ec65cbc7d9275253e6b5cc34b5d10439f158194a3feefa8d53"

        let tags = [
            ["e", direct_reply_hex, "", "reply"],
            ["e", root_note_id_hex, "", "root"],
            ["e", reply_hex, "", "reply"],
            ["e", "7c7d37bc8c04d2ec65cbc7d9275253e6b5cc34b5d10439f158194a3feefa8d54", "", "mention"],
        ]

        let root_note_id = NoteId(hex: root_note_id_hex)!
        let direct_reply_id = NoteId(hex: direct_reply_hex)!
        let reply_id = NoteId(hex: reply_hex)!

        let note = NdbNote(content: "hi", keypair: test_keypair, kind: 1, tags: tags)!
        let refs = interp_event_refs_without_mentions_ndb(note.referenced_noterefs)

        XCTAssertEqual(refs.reduce(into: Array<NoteId>(), { xs, r in
            if let note_id = r.is_thread_id?.note_id { xs.append(note_id) }
        }), [root_note_id])

        XCTAssertEqual(refs.reduce(into: Array<NoteId>(), { xs, r in
            if let note_id = r.is_direct_reply?.note_id { xs.append(note_id) }
        }), [direct_reply_id, reply_id])

        XCTAssertEqual(refs.reduce(into: Array<NoteId>(), { xs, r in
            if let note_id = r.is_reply?.note_id { xs.append(note_id) }
        }), [direct_reply_id, reply_id])
    }

    func test_repost_root() {
        let mention_hex = "7c7d37bc8c04d2ec65cbc7d9275253e6b5cc34b5d10439f158194a3feefa8d52"
        let tags = [
            ["e", mention_hex, "", "mention"],
        ]

        let mention_id = NoteId(hex: mention_hex)!
        let note = NdbNote(content: "hi", keypair: test_keypair, kind: 1, tags: tags)!
        let refs = interp_event_refs_without_mentions_ndb(note.referenced_noterefs)

        XCTAssertEqual(refs.reduce(into: Array<NoteId>(), { xs, r in
            if let note_id = r.is_thread_id?.note_id { xs.append(note_id) }
        }), [])

        XCTAssertEqual(refs.reduce(into: Array<NoteId>(), { xs, r in
            if let note_id = r.is_direct_reply?.note_id { xs.append(note_id) }
        }), [])

        XCTAssertEqual(refs.reduce(into: Array<NoteId>(), { xs, r in
            if let note_id = r.is_reply?.note_id { xs.append(note_id) }
        }), [])
    }
    
    func test_direct_reply_old_nip10() {
        let root_note_id_hex = "7c7d37bc8c04d2ec65cbc7d9275253e6b5cc34b5d10439f158194a3feefa8d52"
        let tags = [
            ["e", root_note_id_hex],
        ]

        let root_note_id = NoteId(hex: root_note_id_hex)!

        let note = NdbNote(content: "hi", keypair: test_keypair, kind: 1, tags: tags)!
        let refs = interp_event_refs_without_mentions_ndb(note.referenced_noterefs)

        XCTAssertEqual(refs.reduce(into: Array<NoteId>(), { xs, r in
            if let note_id = r.is_thread_id?.note_id { xs.append(note_id) }
        }), [root_note_id])

        XCTAssertEqual(refs.reduce(into: Array<NoteId>(), { xs, r in
            if let note_id = r.is_direct_reply?.note_id { xs.append(note_id) }
        }), [root_note_id])
        
        XCTAssertEqual(refs.reduce(into: Array<NoteId>(), { xs, r in
            if let note_id = r.is_reply?.note_id { xs.append(note_id) }
        }), [root_note_id])
    }

    func test_direct_reply_new_nip10() {
        let root_note_id_hex = "7c7d37bc8c04d2ec65cbc7d9275253e6b5cc34b5d10439f158194a3feefa8d52"
        let tags = [
            ["e", root_note_id_hex, "", "root"],
        ]

        let root_note_id = NoteId(hex: root_note_id_hex)!

        let note = NdbNote(content: "hi", keypair: test_keypair, kind: 1, tags: tags)!
        let refs = interp_event_refs_without_mentions_ndb(note.referenced_noterefs)

        XCTAssertEqual(refs.reduce(into: Array<NoteId>(), { xs, r in
            if let note_id = r.is_thread_id?.note_id { xs.append(note_id) }
        }), [root_note_id])

        XCTAssertEqual(refs.reduce(into: Array<NoteId>(), { xs, r in
            if let note_id = r.is_direct_reply?.note_id { xs.append(note_id) }
        }), [root_note_id])
        
        XCTAssertEqual(refs.reduce(into: Array<NoteId>(), { xs, r in
            if let note_id = r.is_reply?.note_id { xs.append(note_id) }
        }), [root_note_id])
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
        let refs = interp_event_refs_without_mentions_ndb(note.referenced_noterefs)

        XCTAssertEqual(refs.reduce(into: Array<NoteId>(), { xs, r in
            if let note_id = r.is_thread_id?.note_id { xs.append(note_id) }
        }), [root_note_id])

        XCTAssertEqual(refs.reduce(into: Array<NoteId>(), { xs, r in
            if let note_id = r.is_direct_reply?.note_id { xs.append(note_id) }
        }), [direct_reply_id, reply_id])

        XCTAssertEqual(refs.reduce(into: Array<NoteId>(), { xs, r in
            if let note_id = r.is_reply?.note_id { xs.append(note_id) }
        }), [direct_reply_id, reply_id])
    }



    func testPerformanceExample() throws {
        // This is an example of a performance test case.
        self.measure {
            // Put the code you want to measure the time of here.
        }
    }

}
