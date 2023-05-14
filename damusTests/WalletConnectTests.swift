//
//  WalletConnectTests.swift
//  damusTests
//
//  Created by William Casarin on 2023-04-02.
//

import XCTest
@testable import damus

final class WalletConnectTests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testWalletBalanceRequest() throws {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
        // Any test you write for XCTest can be annotated as throws and async.
        // Mark your test throws to produce an unexpected failure when your test encounters an uncaught error.
        // Mark your test async to allow awaiting for asynchronous code to complete. Check the results with assertions afterwards.
    }
    
    func get_test_nwc() -> WalletConnectURL {
        let pk = "9d088f4760422443d4699b485e2ac66e565a2f5da1198c55ddc5679458e3f67a"
        let sec = "ff2eefd57196d42089e1b42acc39916d7ecac52e0625bd70597bbd5be14aff18"
        let relay = "wss://relay.getalby.com/v1"
        let str = "nostrwalletconnect://\(pk)?relay=\(relay)&secret=\(sec)"
        
        return WalletConnectURL(str: str)!
    }
    
    func testDoesNWCParse() {
        let pk = "9d088f4760422443d4699b485e2ac66e565a2f5da1198c55ddc5679458e3f67a"
        let sec = "ff2eefd57196d42089e1b42acc39916d7ecac52e0625bd70597bbd5be14aff18"
        let relay = "wss://relay.getalby.com/v1"
        let str = "nostrwalletconnect://\(pk)?relay=\(relay)&secret=\(sec)&lud16=jb55@jb55.com"
        
        let url = WalletConnectURL(str: str)
        XCTAssertNotNil(url)
        guard let url else {
            return
        }
        XCTAssertEqual(url.pubkey, pk)
        XCTAssertEqual(url.keypair.privkey, sec)
        XCTAssertEqual(url.keypair.pubkey, privkey_to_pubkey(privkey: sec))
        XCTAssertEqual(url.relay.id, relay)
        XCTAssertEqual(url.lud16, "jb55@jb55.com")
    }
    
    func testNWCEphemeralRelay() {
        let sec = "8ba3a6b3b57d0f4211bb1ea4d8d1e351a367e9b4ea694746e0a4a452b2bc4d37"
        let pk =  "89446b900c70d62438dcf66756405eea6225ad94dc61f3856f62f9699111a9a6"
        let nwc = WalletConnectURL(str: "nostrwalletconnect://\(pk)?relay=ws://127.0.0.1&secret=\(sec)&lud16=jb55@jb55.com")!
        
        let pool = RelayPool()
        let box = PostBox(pool: pool)
        
        nwc_pay(url: nwc, pool: pool, post: box, invoice: "invoice")
        
        XCTAssertEqual(pool.our_descriptors.count, 0)
        XCTAssertEqual(pool.all_descriptors.count, 1)
        XCTAssertEqual(pool.all_descriptors[0].variant, .nwc)
        XCTAssertEqual(pool.all_descriptors[0].url.id, "ws://127.0.0.1")
        XCTAssertEqual(box.events.count, 1)
        let ev = box.events.first!.value
        XCTAssertEqual(ev.skip_ephemeral, false)
        XCTAssertEqual(ev.remaining.count, 1)
        XCTAssertEqual(ev.remaining[0].relay, "ws://127.0.0.1")
    }

    func testPerformanceExample() throws {
        // This is an example of a performance test case.
        self.measure {
            // Put the code you want to measure the time of here.
        }
    }

}
