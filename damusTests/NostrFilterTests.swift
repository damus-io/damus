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
}
