//
//  NostrFilterTests.swift
//  damusTests
//
//  Created by Daniel D’Aquino on 2024-05-10.
//

import XCTest
@testable import damus

final class NostrFilterTests: XCTestCase {
    func testChunkedWithPubKeys() {
        // Given a NostrFilter with a list of pubkeys
        let test_pubkey_1 = Pubkey(hex: "760f108754eb415561239d4079e71766d87e23f7e71c8e5b00d759e54dd8d082")!
        let test_pubkey_2 = Pubkey(hex: "065eab63e939ea2f2f72f2305886b13e5e301302da67b5fe8a18022b278fe872")!
        let test_pubkey_3 = Pubkey(hex: "aa146d7c6618ebe993702a74c561f54fc046c8a16e388b828cb2f631a1ed9602")!
        let test_pubkey_4 = Pubkey(hex: "2f7108dcd33fb484be3e09cea24a1e96868fbc0842e691ca19db63781801089e")!
        let test_pubkey_5 = Pubkey(hex: "1cc7c458e6b565a856d7c3791f4eb5ca5890b1f2433f452ed7a917f9aa0e5250")!
        let test_pubkey_6 = Pubkey(hex: "2ee1f46a847b6613c33fd766db1e64c7f727c63774fa3ee952261d2c03b81cf2")!
        let test_pubkey_7 = Pubkey(hex: "214664a7ca3236b9dd5f76550d322f390fd70cc12908a2e3ff2cdf50085d4ef2")!
        let test_pubkey_8 = Pubkey(hex: "40255b02f3d8ccd6178d50f5ce1c1ac2867b3d919832176957b021c1816fce2f")!
        let pubkeys: [Pubkey] = [test_pubkey_1, test_pubkey_2, test_pubkey_3, test_pubkey_4]
        let authors: [Pubkey] = [test_pubkey_5, test_pubkey_6, test_pubkey_7, test_pubkey_8]
        let filter = NostrFilter(
            pubkeys: pubkeys,
            authors: authors
        )
        
        let chunked_pubkeys_filters_size_2 = filter.chunked(on: .pubkeys, into: 2)
        XCTAssertEqual(chunked_pubkeys_filters_size_2.count, 2)
        XCTAssertEqual(chunked_pubkeys_filters_size_2[0].pubkeys, [test_pubkey_1, test_pubkey_2])
        XCTAssertEqual(chunked_pubkeys_filters_size_2[1].pubkeys, [test_pubkey_3, test_pubkey_4])
        XCTAssertEqual(chunked_pubkeys_filters_size_2[0].authors, authors)
        XCTAssertEqual(chunked_pubkeys_filters_size_2[1].authors, authors)
        
        let chunked_pubkeys_filters_size_3 = filter.chunked(on: .pubkeys, into: 3)
        XCTAssertEqual(chunked_pubkeys_filters_size_3.count, 2)
        XCTAssertEqual(chunked_pubkeys_filters_size_3[0].pubkeys, [test_pubkey_1, test_pubkey_2, test_pubkey_3])
        XCTAssertEqual(chunked_pubkeys_filters_size_3[1].pubkeys, [test_pubkey_4])
        XCTAssertEqual(chunked_pubkeys_filters_size_3[0].authors, authors)
        XCTAssertEqual(chunked_pubkeys_filters_size_3[1].authors, authors)
        
        let chunked_pubkeys_filters_size_4 = filter.chunked(on: .pubkeys, into: 4)
        XCTAssertEqual(chunked_pubkeys_filters_size_4.count, 1)
        XCTAssertEqual(chunked_pubkeys_filters_size_4[0].pubkeys, [test_pubkey_1, test_pubkey_2, test_pubkey_3, test_pubkey_4])
        XCTAssertEqual(chunked_pubkeys_filters_size_4[0].authors, authors)
        
        let chunked_pubkeys_filters_size_5 = filter.chunked(on: .pubkeys, into: 5)
        XCTAssertEqual(chunked_pubkeys_filters_size_5.count, 1)
        XCTAssertEqual(chunked_pubkeys_filters_size_5[0].pubkeys, [test_pubkey_1, test_pubkey_2, test_pubkey_3, test_pubkey_4])
        XCTAssertEqual(chunked_pubkeys_filters_size_5[0].authors, authors)
        
        let chunked_authors_filters_size_2 = filter.chunked(on: .authors, into: 2)
        XCTAssertEqual(chunked_authors_filters_size_2.count, 2)
        XCTAssertEqual(chunked_authors_filters_size_2[0].authors, [test_pubkey_5, test_pubkey_6])
        XCTAssertEqual(chunked_authors_filters_size_2[1].authors, [test_pubkey_7, test_pubkey_8])
        XCTAssertEqual(chunked_authors_filters_size_2[0].pubkeys, pubkeys)
        XCTAssertEqual(chunked_authors_filters_size_2[1].pubkeys, pubkeys)

        let chunked_authors_filters_size_3 = filter.chunked(on: .authors, into: 3)
        XCTAssertEqual(chunked_authors_filters_size_3.count, 2)
        XCTAssertEqual(chunked_authors_filters_size_3[0].authors, [test_pubkey_5, test_pubkey_6, test_pubkey_7])
        XCTAssertEqual(chunked_authors_filters_size_3[1].authors, [test_pubkey_8])
        XCTAssertEqual(chunked_authors_filters_size_3[0].pubkeys, pubkeys)
        XCTAssertEqual(chunked_authors_filters_size_3[1].pubkeys, pubkeys)
        
        let chunked_authors_filters_size_4 = filter.chunked(on: .authors, into: 4)
        XCTAssertEqual(chunked_authors_filters_size_4.count, 1)
        XCTAssertEqual(chunked_authors_filters_size_4[0].authors, [test_pubkey_5, test_pubkey_6, test_pubkey_7, test_pubkey_8])
        XCTAssertEqual(chunked_authors_filters_size_4[0].pubkeys, pubkeys)
        
        let chunked_authors_filters_size_5 = filter.chunked(on: .authors, into: 5)
        XCTAssertEqual(chunked_authors_filters_size_5.count, 1)
        XCTAssertEqual(chunked_authors_filters_size_5[0].authors, [test_pubkey_5, test_pubkey_6, test_pubkey_7, test_pubkey_8])
        XCTAssertEqual(chunked_authors_filters_size_5[0].pubkeys, pubkeys)
    }

    // MARK: NIP-17/59 kinds through the NdbFilter conversion

    /// The NIP-17/59 kinds are just numbers to nostrdb, but they only reach it if
    /// ``NostrKind`` knows them and the conversion copies them into `NDB_FILTER_KINDS`.
    /// Round-trip the filter back out through `ndb_filter_json` and read what landed.
    func testConversionRoundTripsGiftwrapKinds() throws {
        let filter = NostrFilter(kinds: [.seal, .private_dm, .giftwrap])

        let json = try Self.convertedFilterJson(filter)

        XCTAssertEqual(json["kinds"] as? [Int], [13, 14, 1059],
                       "seal/private_dm/giftwrap should survive the NostrFilter -> NdbFilter conversion")
    }

    /// The inbound giftwrap subscription is `kind 1059` narrowed by `#p: <us>`, so both
    /// fields have to make it across together.
    func testConversionRoundTripsGiftwrapTagFilter() throws {
        let us = try XCTUnwrap(Pubkey(hex: "760f108754eb415561239d4079e71766d87e23f7e71c8e5b00d759e54dd8d082"))
        let filter = NostrFilter(kinds: [.giftwrap], pubkeys: [us])

        let json = try Self.convertedFilterJson(filter)

        XCTAssertEqual(json["kinds"] as? [Int], [1059])
        XCTAssertEqual(json["#p"] as? [String], [us.hex()])
    }

    /// The JSON above only proves the fields were stored. This proves nostrdb actually
    /// *uses* them: a real signed kind-1059 tagged with our pubkey matches, and the same
    /// wrap addressed to someone else does not.
    func testConvertedGiftwrapTagFilterMatchesTheRightWrap() throws {
        let us = generate_new_keypair()
        let someoneElse = generate_new_keypair()
        let sender = generate_new_keypair()

        let ndbFilter = try NdbFilter(from: NostrFilter(kinds: [.giftwrap], pubkeys: [us.pubkey]))

        let toUs = try XCTUnwrap(NostrEvent(content: "wrapped", keypair: sender.to_keypair(),
                                            kind: 1059, tags: [["p", us.pubkey.hex()]]))
        let toSomeoneElse = try XCTUnwrap(NostrEvent(content: "wrapped", keypair: sender.to_keypair(),
                                                     kind: 1059, tags: [["p", someoneElse.pubkey.hex()]]))
        let wrongKind = try XCTUnwrap(NostrEvent(content: "not a wrap", keypair: sender.to_keypair(),
                                                 kind: 1, tags: [["p", us.pubkey.hex()]]))

        XCTAssertEqual(ndb_filter_matches(ndbFilter.unsafePointer, toUs.note.ptr), 1,
                       "a 1059 tagged with our pubkey should match a `kinds: [1059], #p: [us]` filter")
        XCTAssertEqual(ndb_filter_matches(ndbFilter.unsafePointer, toSomeoneElse.note.ptr), 0,
                       "a 1059 addressed to somebody else should not match")
        XCTAssertEqual(ndb_filter_matches(ndbFilter.unsafePointer, wrongKind.note.ptr), 0,
                       "the kind still has to match")
    }

    // MARK: Helpers

    /// Converts `filter` to an `NdbFilter` and reads it back out as JSON via
    /// `ndb_filter_json`, so assertions can be made on what nostrdb actually stored
    /// rather than on the Swift value that went in.
    private static func convertedFilterJson(_ filter: NostrFilter) throws -> [String: Any] {
        let ndbFilter = try NdbFilter(from: filter)

        var buf = [CChar](repeating: 0, count: 4096)
        let len = buf.withUnsafeMutableBufferPointer { ptr in
            ndb_filter_json(ndbFilter.unsafePointer, ptr.baseAddress, Int32(ptr.count))
        }
        XCTAssertGreaterThan(len, 0, "ndb_filter_json should have written the filter out")

        let json = String(cString: buf)
        let data = try XCTUnwrap(json.data(using: .utf8))
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any],
                             "ndb_filter_json produced something that is not a JSON object: \(json)")
    }
}
