//
//  RequestTests.swift
//  damusTests
//
//  Created by Bryan Montz on 2/17/23.
//

import XCTest
@testable import damus

final class RequestTests: XCTestCase {
    
    func testMakeUnsubscribeRequest() {
        let request = NostrRequest.unsubscribe("64FD064D-EB9E-4771-8255-8D16981B920B")
        let result = make_nostr_req(request)
        let expectedResult = "[\"CLOSE\",\"64FD064D-EB9E-4771-8255-8D16981B920B\"]"
        XCTAssertEqual(result, expectedResult)
    }

    func testMakeAuthRequest() {
        let challenge_string = "8bc847dd-f2f6-4b3a-9c8a-71776ad9b071"
        let url = RelayURL("wss://example.com")!
        let relayInfo = RelayInfo(read: true, write: true)
        let relayDescriptor = RelayDescriptor(url: url, info: relayInfo)
        let relayConnection = RelayConnection(url: url) { _ in
        } processEvent: { _ in
        }

        let relay = Relay(descriptor: relayDescriptor, connection: relayConnection)
        let event = make_auth_request(keypair: FullKeypair.init(pubkey: Pubkey.empty, privkey: Privkey.empty), challenge_string: challenge_string, relay: relay)!

        let result = make_nostr_auth_event(ev: event)
        let json = try! JSONSerialization.jsonObject(with: result!.data(using: .utf8)!, options: []) as! [Any]

        XCTAssertEqual(json[0] as! String, "AUTH")
        let dictionary = json[1] as! [String: Any]
        XCTAssertEqual(dictionary["content"] as! String, "")
        XCTAssertEqual(dictionary["kind"] as! Int, 22242)
        XCTAssertEqual(dictionary["sig"] as! String, String(repeating: "0", count: 128))
        XCTAssertEqual(dictionary["pubkey"] as! String, String(repeating: "0", count: 64))
        let tags = dictionary["tags"] as! [[String]]
        XCTAssertEqual(tags.first { $0[0] == "relay" }![1], "wss://example.com")
        XCTAssertEqual(tags.first { $0[0] == "challenge" }![1], challenge_string)
        XCTAssertEqual(dictionary["id"] as! String, String(repeating: "0", count: 64))
    }

    /* FIXME: these tests depend on order of json fields which is undefined
    func testMakePushEvent() {
        let now = Int64(Date().timeIntervalSince1970)
        let event = NostrEvent(id: "59c1cf11a3e9e128c6fd5402f41e8ae0c0c7fbab570203d7410518be68c3115f",
                               content: "Testing",
                               pubkey: "d9fa34214aa9d151c4f4db843e9c2af4f246bab4205137731f91bcfa44d66a62",
                               kind: 1,
                               createdAt: now)
        let result = make_nostr_req(.event(event))
        let expectedResult = "[\"EVENT\",{\"pubkey\":\"d9fa34214aa9d151c4f4db843e9c2af4f246bab4205137731f91bcfa44d66a62\",\"content\":\"Testing\",\"id\":\"59c1cf11a3e9e128c6fd5402f41e8ae0c0c7fbab570203d7410518be68c3115f\",\"created_at\":\(now),\"sig\":\"\",\"kind\":1,\"tags\":[]}]"
        XCTAssertEqual(result, expectedResult)
    }
    
    func testMakeSubscriptionRequest() {
        let filter = NostrFilter(kinds: [.contacts], limit: 1, authors: ["d9fa34214aa9d151c4f4db843e9c2af4f246bab4205137731f91bcfa44d66a62"])
        let subscribe = NostrSubscribe(filters: [filter], sub_id: "31C737B7-C8F9-41DD-8707-325974F279A4")
        let result = make_nostr_req(.subscribe(subscribe))
        let expectedResult = "[\"REQ\",\"31C737B7-C8F9-41DD-8707-325974F279A4\",{\"kinds\":[3],\"authors\":[\"d9fa34214aa9d151c4f4db843e9c2af4f246bab4205137731f91bcfa44d66a62\"],\"limit\":1}]"
        XCTAssertEqual(result, expectedResult)
    }
     */
}
