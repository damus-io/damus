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
        // Test an NWC url format which is not technically NIP-47 and RFC 3986 compliant, but still commonly used (by Alby, for example)
        // See Github issue #1547 for details on why this URL is non-compliant
        // This test URL also features:
        // - `nostrwalletconnect` scheme
        // - A non-url-encoded relay parameter
        // - lud16 parameter
        let pk = Pubkey(hex: "9d088f4760422443d4699b485e2ac66e565a2f5da1198c55ddc5679458e3f67a")!
        let sec = Privkey(hex: "ff2eefd57196d42089e1b42acc39916d7ecac52e0625bd70597bbd5be14aff18")!
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

        // Test an NWC url format which is NIP-47 and RFC 3986 compliant
        // This test URL also features:
        // - `nostr+walletconnect` scheme
        // - A url-encoded relay parameter
        // - No lud16 parameter
        let pk_2 = Pubkey(hex: "b889ff5b1513b641e2a139f661a661364979c5beee91842f8f0ef42ab558e9d4")!
        let sec_2 = Privkey(hex: "71a8c14c1407c113601079c4302dab36460f0ccd0ad506f1f2dc73b5100e4f3c")!
        let relay_2 = "wss://relay.damus.io"
        let str_2 = "nostr+walletconnect:b889ff5b1513b641e2a139f661a661364979c5beee91842f8f0ef42ab558e9d4?relay=wss%3A%2F%2Frelay.damus.io&secret=71a8c14c1407c113601079c4302dab36460f0ccd0ad506f1f2dc73b5100e4f3c"
        
        let url_2 = WalletConnectURL(str: str_2)
        XCTAssertNotNil(url_2)
        guard let url_2 else {
            return
        }
        XCTAssertEqual(url_2.pubkey, pk_2)
        XCTAssertEqual(url_2.keypair.privkey, sec_2)
        XCTAssertEqual(url_2.keypair.pubkey, privkey_to_pubkey(privkey: sec_2))
        XCTAssertEqual(url_2.relay.id, relay_2)
    }
    
    func testNWCEphemeralRelay() {
        let sec = "8ba3a6b3b57d0f4211bb1ea4d8d1e351a367e9b4ea694746e0a4a452b2bc4d37"
        let pk =  "89446b900c70d62438dcf66756405eea6225ad94dc61f3856f62f9699111a9a6"
        let nwc = WalletConnectURL(str: "nostrwalletconnect://\(pk)?relay=ws://127.0.0.1&secret=\(sec)&lud16=jb55@jb55.com")!
        
        let pool = RelayPool(ndb: .empty)
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
