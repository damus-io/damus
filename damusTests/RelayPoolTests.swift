//
//  RelayPoolTests.swift
//  damusTests
//
//  Created by kernelkind on 12/16/23.
//

import Foundation

import XCTest
@testable import damus

final class RelayPoolTests: XCTestCase {
    
    override func setUpWithError() throws {
    }

    override func tearDownWithError() throws {
    }
    
    @MainActor
    func testAddRelay_ValidRelayURL_NoErrors() async {
        await testAddRelays(urls: [
            "wss://relay.damus.io"
        ])
    }

    @MainActor
    func testAddRelay_TwoSameURLs_ThrowsRelayAlreadyExists() async {
        await testAddRelays(urls: [
            "wss://relay.damus.io",
            "wss://relay.damus.io"
        ], expectedError: .RelayAlreadyExists)
    }

    @MainActor
    func testAddRelay_OneExtraneousSlashURL_ThrowsRelayAlreadyExists() async {
        await testAddRelays(urls: [
            "wss://relay.damus.io",
            "wss://relay.damus.io/"
        ], expectedError: .RelayAlreadyExists)
    }

    @MainActor
    func testAddRelay_MultipleExtraneousSlashURL_ThrowsRelayAlreadyExists() async {
        await testAddRelays(urls: [
            "wss://relay.damus.io",
            "wss://relay.damus.io///"
        ], expectedError: .RelayAlreadyExists)
    }

    @MainActor
    func testAddRelay_ExtraSlashURLFirst_ThrowsRelayAlreadyExists() async {
        await testAddRelays(urls: [
            "wss://relay.damus.io///",
            "wss://relay.damus.io"
        ], expectedError: .RelayAlreadyExists)
    }

}

/// Adds relay URLs to a pool and verifies duplicate URL handling.
@MainActor
func testAddRelays(urls: [String], expectedError: RelayPool.RelayError? = nil) async {
    let relayPool = RelayPool(ndb: nil)

    do {
        for relay in urls {
            guard let url = RelayURL(relay) else {
                XCTFail("Invalid URL encountered: \(relay)")
                return
            }

            let descriptor = RelayPool.RelayDescriptor(url: url, info: .readWrite)
            try await relayPool.add_relay(descriptor)
        }

        if expectedError != nil {
            XCTFail("Expected \(expectedError!) error, but no error was thrown.")
        }
    } catch let error as RelayPool.RelayError where expectedError == .RelayAlreadyExists {
        XCTAssertEqual(error, expectedError!, "Expected RelayAlreadyExists error, got \(error)")
    } catch {
        XCTFail("An unexpected error was thrown: \(error)")
    }
}


