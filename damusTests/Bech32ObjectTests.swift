//
//  Bech32ObjectTests.swift
//  damusTests
//
//  Created by KernelKind on 1/5/24.
//
//  This file contains tests that are adapted from the nostr-sdk-ios project.
//  Original source:
//  https://github.com/nostr-sdk/nostr-sdk-ios/blob/main/Tests/NostrSDKTests/MetadataCodingTests.swift
//

import XCTest
@testable import damus

class Bech32ObjectTests: XCTestCase {
    func testTLVParsing_NeventHasRelaysNoAuthorNoKind_ValidContent() throws {
        let content = "nevent1qqstna2yrezu5wghjvswqqculvvwxsrcvu7uc0f78gan4xqhvz49d9spr3mhxue69uhkummnw3ez6un9d3shjtn4de6x2argwghx6egpr4mhxue69uhkummnw3ez6ur4vgh8wetvd3hhyer9wghxuet5nxnepm"
        let expectedNoteIDHex = "b9f5441e45ca39179320e0031cfb18e34078673dcc3d3e3a3b3a981760aa5696"
        let relays = ["wss://nostr-relay.untethr.me", "wss://nostr-pub.wellorder.net"].compactMap(RelayURL.init)
        guard let noteid = hex_decode_noteid(expectedNoteIDHex) else {
            XCTFail("Parsing note ID failed")
            return
        }
        
        let expectedObject = Bech32Object.nevent(NEvent(noteid: noteid, relays: relays))
        guard let actualObject = Bech32Object.parse(content) else {
            XCTFail("Invalid Object")
            return
        }
        
        XCTAssertEqual(expectedObject, actualObject)
    }
    
    func testTLVParsing_NeventHasRelaysNoAuthorHasKind_ValidContent() throws {
        let content = "nevent1qqstna2yrezu5wghjvswqqculvvwxsrcvu7uc0f78gan4xqhvz49d9spr3mhxue69uhkummnw3ez6un9d3shjtn4de6x2argwghx6egpr4mhxue69uhkummnw3ez6ur4vgh8wetvd3hhyer9wghxuet5qvzqqqqqqyjyqz7d"
        let expectedNoteIDHex = "b9f5441e45ca39179320e0031cfb18e34078673dcc3d3e3a3b3a981760aa5696"
        let relays = ["wss://nostr-relay.untethr.me", "wss://nostr-pub.wellorder.net"].compactMap(RelayURL.init)
        guard let noteid = hex_decode_noteid(expectedNoteIDHex) else {
            XCTFail("Parsing note ID failed")
            return
        }
        
        let expectedObject = Bech32Object.nevent(NEvent(noteid: noteid, relays: relays, kind: 1))
        guard let actualObject = Bech32Object.parse(content) else {
            XCTFail("Invalid Object")
            return
        }
        
        XCTAssertEqual(expectedObject, actualObject)
    }
    
    func testTLVParsing_NeventHasRelaysHasAuthorHasKind_ValidContent() throws {
        let content = "nevent1qqstna2yrezu5wghjvswqqculvvwxsrcvu7uc0f78gan4xqhvz49d9spr3mhxue69uhkummnw3ez6un9d3shjtn4de6x2argwghx6egpr4mhxue69uhkummnw3ez6ur4vgh8wetvd3hhyer9wghxuet5qgsrhuxx8l9ex335q7he0f09aej04zpazpl0ne2cgukyawd24mayt8grqsqqqqqpw4032x"
        
        let expectedNoteIDHex = "b9f5441e45ca39179320e0031cfb18e34078673dcc3d3e3a3b3a981760aa5696"
        let relays = ["wss://nostr-relay.untethr.me", "wss://nostr-pub.wellorder.net"].compactMap(RelayURL.init)
        guard let noteid = hex_decode_noteid(expectedNoteIDHex) else {
            XCTFail("Parsing note ID failed")
            return
        }
        guard let author = try bech32_decode("npub180cvv07tjdrrgpa0j7j7tmnyl2yr6yr7l8j4s3evf6u64th6gkwsyjh6w6") else {
            XCTFail()
            return
        }
        
        let expectedObject = Bech32Object.nevent(NEvent(noteid: noteid, relays: relays, author: Pubkey(author.data), kind: 1))
        guard let actualObject = Bech32Object.parse(content) else {
            XCTFail("Invalid Object")
            return
        }
        
        XCTAssertEqual(expectedObject, actualObject)
    }
    
    func testTLVParsing_NProfileExample_ValidContent() throws {
        let content = "nprofile1qqsrhuxx8l9ex335q7he0f09aej04zpazpl0ne2cgukyawd24mayt8gpp4mhxue69uhhytnc9e3k7mgpz4mhxue69uhkg6nzv9ejuumpv34kytnrdaksjlyr9p"
        guard let author = try bech32_decode("npub180cvv07tjdrrgpa0j7j7tmnyl2yr6yr7l8j4s3evf6u64th6gkwsyjh6w6") else {
            XCTFail()
            return
        }
        let relays = ["wss://r.x.com", "wss://djbas.sadkb.com"].compactMap(RelayURL.init)

        let expectedObject = Bech32Object.nprofile(NProfile(author: Pubkey(author.data), relays: relays))
        guard let actualObject = Bech32Object.parse(content) else {
            XCTFail("Invalid Object")
            return
        }
        
        XCTAssertEqual(expectedObject, actualObject)
    }
    
    func testTLVParsing_NRelayExample_ValidContent() throws {
        let content = "nrelay1qqt8wumn8ghj7un9d3shjtnwdaehgu3wvfskueq4r295t"
        let relay = "wss://relay.nostr.band"
        
        let expectedObject = Bech32Object.nrelay(relay)
        let actualObject = Bech32Object.parse(content)
        
        XCTAssertEqual(expectedObject, actualObject)
    }
    
    func testTLVParsing_NaddrExample_ValidContent() throws {
        let content = "naddr1qqxnzdesxqmnxvpexqunzvpcqyt8wumn8ghj7un9d3shjtnwdaehgu3wvfskueqzypve7elhmamff3sr5mgxxms4a0rppkmhmn7504h96pfcdkpplvl2jqcyqqq823cnmhuld"
        
        guard let author = try bech32_decode("npub1tx0k0a7lw62vvqax6p3ku90tccgdka7ul4radews2wrdsg0m865szf9fw6") else {
            XCTFail("Can't decode npub")
            return
        }
        let relays = ["wss://relay.nostr.band"].compactMap(RelayURL.init)
        let identifier = "1700730909108"
        let kind: UInt32 = 30023
        
        let expectedObject = Bech32Object.naddr(NAddr(identifier: identifier, author: Pubkey(author.data), relays: relays, kind: kind))
        let actualObject = Bech32Object.parse(content)
        
        XCTAssertEqual(expectedObject, actualObject)
    }
    
    func testTLVEncoding_NeventHasRelaysNoAuthorNoKind_ValidContent() throws {
        guard let noteid = hex_decode_noteid("b9f5441e45ca39179320e0031cfb18e34078673dcc3d3e3a3b3a981760aa5696") else {
            XCTFail("Parsing note ID failed")
            return
        }
        
        let relays = ["wss://nostr-relay.untethr.me", "wss://nostr-pub.wellorder.net"].compactMap(RelayURL.init)

        let expectedEncoding = "nevent1qqstna2yrezu5wghjvswqqculvvwxsrcvu7uc0f78gan4xqhvz49d9spr3mhxue69uhkummnw3ez6un9d3shjtn4de6x2argwghx6egpr4mhxue69uhkummnw3ez6ur4vgh8wetvd3hhyer9wghxuet5nxnepm"
        
        let actualEncoding = Bech32Object.encode(.nevent(NEvent(noteid: noteid, relays: relays)))
        
        XCTAssertEqual(expectedEncoding, actualEncoding)
    }
    
    func testTLVEncoding_NeventHasRelaysNoAuthorHasKind_ValidContent() throws {
        guard let noteid = hex_decode_noteid("b9f5441e45ca39179320e0031cfb18e34078673dcc3d3e3a3b3a981760aa5696") else {
            XCTFail()
            return
        }
        
        let relays = [
            "wss://nostr-relay.untethr.me",
            "wss://nostr-pub.wellorder.net"
        ].compactMap(RelayURL.init)

        let expectedEncoding = "nevent1qqstna2yrezu5wghjvswqqculvvwxsrcvu7uc0f78gan4xqhvz49d9spr3mhxue69uhkummnw3ez6un9d3shjtn4de6x2argwghx6egpr4mhxue69uhkummnw3ez6ur4vgh8wetvd3hhyer9wghxuet5qvzqqqqqqyjyqz7d"
        
        let actualEncoding = Bech32Object.encode(.nevent(NEvent(noteid: noteid, relays: relays, kind: 1)))
        
        XCTAssertEqual(expectedEncoding, actualEncoding)
    }
    
    func testTLVEncoding_NeventHasRelaysHasAuthorHasKind_ValidContent() throws {
        guard let noteid = hex_decode_noteid("b9f5441e45ca39179320e0031cfb18e34078673dcc3d3e3a3b3a981760aa5696") else {
            XCTFail("Parsing note ID failed")
            return
        }
        guard let author = try bech32_decode("npub180cvv07tjdrrgpa0j7j7tmnyl2yr6yr7l8j4s3evf6u64th6gkwsyjh6w6") else {
            XCTFail()
            return
        }
        
        let relays = ["wss://nostr-relay.untethr.me", "wss://nostr-pub.wellorder.net"].compactMap(RelayURL.init)

        let expectedEncoding = "nevent1qqstna2yrezu5wghjvswqqculvvwxsrcvu7uc0f78gan4xqhvz49d9spr3mhxue69uhkummnw3ez6un9d3shjtn4de6x2argwghx6egpr4mhxue69uhkummnw3ez6ur4vgh8wetvd3hhyer9wghxuet5qgsrhuxx8l9ex335q7he0f09aej04zpazpl0ne2cgukyawd24mayt8grqsqqqqqpw4032x"

        let actualEncoding = Bech32Object.encode(.nevent(NEvent(noteid: noteid, relays: relays, author: Pubkey(author.data), kind: 1)))
        
        XCTAssertEqual(expectedEncoding, actualEncoding)
    }
    
    func testTLVEncoding_NProfileExample_ValidContent() throws {
        guard let author = try bech32_decode("npub180cvv07tjdrrgpa0j7j7tmnyl2yr6yr7l8j4s3evf6u64th6gkwsyjh6w6") else {
            XCTFail()
            return
        }
        
        let relays = [
            "wss://r.x.com",
            "wss://djbas.sadkb.com"
        ].compactMap(RelayURL.init)

        let expectedEncoding = "nprofile1qqsrhuxx8l9ex335q7he0f09aej04zpazpl0ne2cgukyawd24mayt8gpp4mhxue69uhhytnc9e3k7mgpz4mhxue69uhkg6nzv9ejuumpv34kytnrdaksjlyr9p"
        
        let actualEncoding = Bech32Object.encode(.nprofile(NProfile(author: Pubkey(author.data), relays: relays)))
        
        XCTAssertEqual(expectedEncoding, actualEncoding)
    }
    
    func testTLVEncoding_NRelayExample_ValidContent() throws {
        let relay = "wss://relay.nostr.band"
        
        let expectedEncoding = "nrelay1qqt8wumn8ghj7un9d3shjtnwdaehgu3wvfskueq4r295t"
        
        let actualEncoding = Bech32Object.encode(.nrelay(relay))
        
        XCTAssertEqual(expectedEncoding, actualEncoding)
    }
    
    func testTLVEncoding_NaddrExample_ValidContent() throws {
        guard let author = try bech32_decode("npub1tx0k0a7lw62vvqax6p3ku90tccgdka7ul4radews2wrdsg0m865szf9fw6") else {
            XCTFail()
            return
        }
        
        let relays = ["wss://relay.nostr.band"].compactMap(RelayURL.init)
        let identifier = "1700730909108"
        let kind: UInt32 = 30023
        
        let expectedEncoding = "naddr1qqxnzdesxqmnxvpexqunzvpcqyt8wumn8ghj7un9d3shjtnwdaehgu3wvfskueqzypve7elhmamff3sr5mgxxms4a0rppkmhmn7504h96pfcdkpplvl2jqcyqqq823cnmhuld"
        
        let actualEncoding = Bech32Object.encode(.naddr(NAddr(identifier: identifier, author: Pubkey(author.data), relays: relays, kind: kind)))
        
        XCTAssertEqual(expectedEncoding, actualEncoding)
    }
}
