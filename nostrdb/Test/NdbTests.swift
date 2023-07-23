//
//  NDBIterTests.swift
//  damusTests
//
//  Created by William Casarin on 2023-07-21.
//

import XCTest
@testable import damus

final class NdbTests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func test_ndb_note() throws {
        let note = NdbNote.owned_from_json(json: test_contact_list_json)
        XCTAssertNotNil(note)
        guard let note else { return }

        let id = "20d0ff27d6fcb13de8366328c5b1a7af26bcac07f2e558fbebd5e9242e608c09"
        let pubkey = "32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245"
        XCTAssertEqual(hex_encode(note.id), id)
        XCTAssertEqual(hex_encode(note.pubkey), pubkey)

        XCTAssertEqual(note.count, 34058)
        XCTAssertEqual(note.kind, 3)
        XCTAssertEqual(note.created_at, 1689904312)

        let expected_count: UInt16 = 786
        XCTAssertEqual(note.tags().count, expected_count)
        XCTAssertEqual(note.tags().reduce(0, { sum, _ in sum + 1 }), expected_count)

        var count = 0
        var tags = 0
        var total_count_stored = 0
        var total_count_iter = 0
        //let tags = note.tags()
        for tag in note.tags() {
            total_count_stored += Int(tag.count)

            if tags == 0 || tags == 1 || tags == 2 {
                XCTAssertEqual(tag.count, 3)
            }

            if tags == 6 {
                XCTAssertEqual(tag.count, 2)
            }

            if tags == 7 {
                XCTAssertEqual(tag[2]?.string(), "wss://nostr-pub.wellorder.net")
            }

            for elem in tag {
                print("tag[\(tags)][\(elem.index)]")
                total_count_iter += 1
            }

            tags += 1
        }

        XCTAssertEqual(tags, 786)
        XCTAssertEqual(total_count_stored, total_count_iter)
    }

    func test_decode_perf() throws {
        // This is an example of a performance test case.
        self.measure {
            _ = NdbNote.owned_from_json(json: test_contact_list_json)
        }
    }

    func test_iteration_perf() throws {
        guard let note = NdbNote.owned_from_json(json: test_contact_list_json) else {
            XCTAssert(false)
            return
        }

        var count = 0
        for tag in note.tags() {
            for elem in tag {
                print("iter_elem \(elem.string())")
                /*
                for _ in elem {
                    count += 1
                }
                 */
            }
            count += 1
        }

        XCTAssertEqual(count, 786)
    }

}

