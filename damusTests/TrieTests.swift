//
//  TrieTests.swift
//  damusTests
//
//  Created by Terry Yiu on 6/26/23.
//

import XCTest
@testable import damus

final class TrieTests: XCTestCase {

    func testFind() throws {
        let trie = Trie<String>()

        let keys = ["foobar", "food", "foo", "somethingelse", "duplicate", "duplicate"]
        keys.forEach {
            trie.insert(key: $0, value: $0)
        }

        let allResults = trie.find(key: "")
        XCTAssertEqual(Set(allResults), Set(["foobar", "food", "foo", "somethingelse", "duplicate"]))

        let fooResults = trie.find(key: "foo")
        XCTAssertEqual(fooResults.first, "foo")
        XCTAssertEqual(Set(fooResults), Set(["foobar", "food", "foo"]))

        let foodResults = trie.find(key: "food")
        XCTAssertEqual(foodResults, ["food"])

        let ooResults = trie.find(key: "oo")
        XCTAssertEqual(Set(ooResults), Set(["foobar", "food", "foo"]))

        let aResults = trie.find(key: "a")
        XCTAssertEqual(Set(aResults), Set(["foobar", "duplicate"]))

        let notFoundResults = trie.find(key: "notfound")
        XCTAssertEqual(notFoundResults, [])

        // Sanity check that the root node has children.
        XCTAssertTrue(trie.hasChildren)

        // Sanity check that the root node has no values.
        XCTAssertFalse(trie.hasValues)
    }

    func testRemove() {
        let trie = Trie<String>()

        let keys = ["foobar", "food", "foo", "somethingelse", "duplicate", "duplicate"]
        keys.forEach {
            trie.insert(key: $0, value: $0)
        }

        keys.forEach {
            trie.remove(key: $0, value: $0)
        }

        let allResults = trie.find(key: "")
        XCTAssertTrue(allResults.isEmpty)

        let fooResults = trie.find(key: "foo")
        XCTAssertTrue(fooResults.isEmpty)

        let foodResults = trie.find(key: "food")
        XCTAssertTrue(foodResults.isEmpty)

        let ooResults = trie.find(key: "oo")
        XCTAssertTrue(ooResults.isEmpty)

        let aResults = trie.find(key: "a")
        XCTAssertTrue(aResults.isEmpty)

        // Verify that removal of values from all the keys that were inserted in the trie previously also resulted in the cleanup of the trie.
        XCTAssertFalse(trie.hasChildren)
        XCTAssertFalse(trie.hasValues)
    }

}
