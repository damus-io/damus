//
//  AuthIntegrationTests.swift
//  damusTests
//
//  Created by Charlie Fish on 12/22/23.
//

import XCTest
@testable import damus

final class AuthIntegrationTests: XCTestCase {
    /*
    func testAuthIntegrationFilterNostrWine() {
        // Create relay pool and connect to `wss://filter.nostr.wine`
        let relay_url = RelayURL("wss://filter.nostr.wine")!
        var received_messages: [String] = []
        var sent_messages: [String] = []
        let keypair: Keypair = generate_new_keypair().to_keypair()
        let pool = RelayPool(ndb: Ndb.test, keypair: keypair)
        pool.message_received_function = { obj in
            let str = obj.0
            let descriptor = obj.1

            if descriptor.url.id != relay_url.id {
                XCTFail("The descriptor we recieved the message from should equal the relayURL")
            }

            received_messages.append(str)
        }
        pool.message_sent_function = { obj in
            let str = obj.0
            let relay = obj.1

            if relay.descriptor.url.id != relay_url.id {
                XCTFail("The descriptor we sent the message to should equal the relayURL")
            }

            sent_messages.append(str)
        }
        XCTAssertEqual(pool.relays.count, 0)
        let relay_descriptor = RelayDescriptor.init(url: relay_url, info: .rw)
        try! pool.add_relay(relay_descriptor)
        XCTAssertEqual(pool.relays.count, 1)
        let connection_expectation = XCTestExpectation(description: "Waiting for connection")
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            if pool.num_connected == 1 {
                connection_expectation.fulfill()
                timer.invalidate()
            }
        }
        wait(for: [connection_expectation], timeout: 30.0)
        XCTAssertEqual(pool.num_connected, 1)
        // Assert that AUTH message has been received
        XCTAssertTrue(received_messages.count >= 1, "expected recieved_messages to be >= 1")
        guard let msg = received_messages[safe: 0],
              let dat = msg.data(using: .utf8),
              let json_received = try? JSONSerialization.jsonObject(with: dat, options: []) as? [Any]
        else {
            XCTAssert(false)
            return
        }
        XCTAssertEqual(json_received[0] as! String, "AUTH")
        // Assert that we've replied with the AUTH response
        XCTAssertEqual(sent_messages.count, 1)
        let json_sent = try! JSONSerialization.jsonObject(with: sent_messages[0].data(using: .utf8)!, options: []) as! [Any]
        XCTAssertEqual(json_sent[0] as! String, "AUTH")
        let sent_msg = json_sent[1] as! [String: Any]
        XCTAssertEqual(sent_msg["kind"] as! Int, 22242)
        XCTAssertEqual((sent_msg["tags"] as! [[String]]).first { $0[0] == "challenge" }![1], json_received[1] as! String)
    }
     */

    func testAuthIntegrationRelayDamusIo() {
        // Create relay pool and connect to `wss://relay.damus.io`
        let relay_url = RelayURL("wss://relay.damus.io")!
        var received_messages: [String] = []
        var sent_messages: [String] = []
        let keypair: Keypair = generate_new_keypair().to_keypair()
        let pool = RelayPool(ndb: Ndb.test, keypair: keypair)
        pool.message_received_function = { obj in
            let str = obj.0
            let descriptor = obj.1

            if descriptor.url.id != relay_url.id {
                XCTFail("The descriptor we recieved the message from should equal the relayURL")
            }

            received_messages.append(str)
        }
        pool.message_sent_function = { obj in
            let str = obj.0
            let relay = obj.1

            if relay.descriptor.url.id != relay_url.id {
                XCTFail("The descriptor we sent the message to should equal the relayURL")
            }

            sent_messages.append(str)
        }
        XCTAssertEqual(pool.relays.count, 0)
        let relay_descriptor = RelayDescriptor.init(url: relay_url, info: .rw)
        try! pool.add_relay(relay_descriptor)
        XCTAssertEqual(pool.relays.count, 1)
        let connection_expectation = XCTestExpectation(description: "Waiting for connection")
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            if pool.num_connected == 1 {
                connection_expectation.fulfill()
                timer.invalidate()
            }
        }
        wait(for: [connection_expectation], timeout: 30.0)
        XCTAssertEqual(pool.num_connected, 1)
        // Assert that no AUTH messages have been received
        XCTAssertEqual(received_messages.count, 0)
    }

    func testAuthIntegrationNostrWine() {
        // Create relay pool and connect to `wss://nostr.wine`
        let relay_url = RelayURL("wss://nostr.wine")!
        var received_messages: [String] = []
        var sent_messages: [String] = []
        let keypair: Keypair = generate_new_keypair().to_keypair()
        let pool = RelayPool(ndb: Ndb.test, keypair: keypair)
        pool.message_received_function = { obj in
            let str = obj.0
            let descriptor = obj.1

            if descriptor.url.id != relay_url.id {
                XCTFail("The descriptor we recieved the message from should equal the relayURL")
            }

            received_messages.append(str)
        }
        pool.message_sent_function = { obj in
            let str = obj.0
            let relay = obj.1

            if relay.descriptor.url.id != relay_url.id {
                XCTFail("The descriptor we sent the message to should equal the relayURL")
            }

            sent_messages.append(str)
        }
        XCTAssertEqual(pool.relays.count, 0)
        let relay_descriptor = RelayDescriptor.init(url: relay_url, info: .rw)
        try! pool.add_relay(relay_descriptor)
        XCTAssertEqual(pool.relays.count, 1)
        let connection_expectation = XCTestExpectation(description: "Waiting for connection")
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            if pool.num_connected == 1 {
                connection_expectation.fulfill()
                timer.invalidate()
            }
        }
        wait(for: [connection_expectation], timeout: 30.0)
        XCTAssertEqual(pool.num_connected, 1)
        // Assert that no AUTH messages have been received
        XCTAssertEqual(received_messages.count, 0)
        // Generate UUID for subscription_id
        let uuid = UUID().uuidString
        // Send `["REQ", subscription_id, {"kinds": [4]}]`
        let subscribe = NostrSubscribe(filters: [
            NostrFilter(kinds: [.dm])
        ], sub_id: uuid)
        pool.send(NostrRequest.subscribe(subscribe))
        // Wait for AUTH message to have been received & sent
        let msg_expectation = XCTestExpectation(description: "Waiting for messages")
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            if received_messages.count >= 2 && sent_messages.count >= 2 {
                msg_expectation.fulfill()
                timer.invalidate()
            }
        }
        wait(for: [msg_expectation], timeout: 30.0)
        // Assert that AUTH message has been received
        XCTAssertTrue(received_messages.count >= 1, "expected recieved_messages to be >= 1")
        let json_received = try! JSONSerialization.jsonObject(with: received_messages[0].data(using: .utf8)!, options: []) as! [Any]
        XCTAssertEqual(json_received[0] as! String, "AUTH")
        // Assert that we've replied with the AUTH response
        XCTAssertEqual(sent_messages.count, 2)
        let json_sent = try! JSONSerialization.jsonObject(with: sent_messages[1].data(using: .utf8)!, options: []) as! [Any]
        XCTAssertEqual(json_sent[0] as! String, "AUTH")
        let sent_msg = json_sent[1] as! [String: Any]
        XCTAssertEqual(sent_msg["kind"] as! Int, 22242)
        XCTAssertEqual((sent_msg["tags"] as! [[String]]).first { $0[0] == "challenge" }![1], json_received[1] as! String)
    }

}
