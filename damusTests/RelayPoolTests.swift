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
    
    func testAddRelay_ValidRelayURL_NoErrors() {
        testAddRelays(urls: [
            "wss://relay.damus.io"
        ])
    }
    
    func testAddRelay_TwoSameURLs_ThrowsRelayAlreadyExists() {
        testAddRelays(urls: [
            "wss://relay.damus.io",
            "wss://relay.damus.io"
        ], expectedError: .RelayAlreadyExists)
    }
    
    func testAddRelay_OneExtraneousSlashURL_ThrowsRelayAlreadyExists() {
        testAddRelays(urls: [
            "wss://relay.damus.io",
            "wss://relay.damus.io/"
        ], expectedError: .RelayAlreadyExists)
    }

    func testAddRelay_MultipleExtraneousSlashURL_ThrowsRelayAlreadyExists() {
        testAddRelays(urls: [
            "wss://relay.damus.io",
            "wss://relay.damus.io///"
        ], expectedError: .RelayAlreadyExists)
    }
    
    func testAddRelay_ExtraSlashURLFirst_ThrowsRelayAlreadyExists() {
        testAddRelays(urls: [
            "wss://relay.damus.io///",
            "wss://relay.damus.io"
        ], expectedError: .RelayAlreadyExists)
    }
}

func testAddRelays(urls: [String], expectedError: RelayError? = nil) {
    let ndb = Ndb()!
    let relayPool = RelayPool(ndb: ndb)
    let info = RelayInfo(read: true, write: true)

    do {
        for relay in urls {
            guard let url = RelayURL(relay) else {
                XCTFail("Invalid URL encountered: \(relay)")
                return
            }

            let descriptor = RelayDescriptor(url: url, info: info)
            try relayPool.add_relay(descriptor)
        }

        if expectedError != nil {
            XCTFail("Expected \(expectedError!) error, but no error was thrown.")
        }
    } catch let error as RelayError where expectedError == .RelayAlreadyExists {
        XCTAssertEqual(error, expectedError!, "Expected RelayAlreadyExists error, got \(error)")
    } catch {
        XCTFail("An unexpected error was thrown: \(error)")
    }
}


