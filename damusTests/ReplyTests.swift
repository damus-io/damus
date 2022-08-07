//
//  ReplyTests.swift
//  damusTests
//
//  Created by William Casarin on 2022-05-08.
//

import XCTest
@testable import damus

class ReplyTests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }
    
    func testMentionIsntReply() throws {
        let content = "this is #[0] a mention"
        let tags = [["e", "event_id"]]
        let blocks = parse_mentions(content: content, tags: tags)
        let event_refs = interpret_event_refs(blocks: blocks, tags: tags)
        
        XCTAssertEqual(event_refs.count, 1)
        
        let ref = event_refs[0]
        
        XCTAssertNil(ref.is_reply)
        XCTAssertNil(ref.is_thread_id)
        XCTAssertNil(ref.is_direct_reply)
        XCTAssertEqual(ref.is_mention!.type, .event)
        XCTAssertEqual(ref.is_mention!.ref.ref_id, "event_id")
    }
    
    func testUrlAnchorsAreNotHashtags() {
        let content = "this is my link: https://jb55.com/index.html#buybitcoin this is not a hashtag!"
        let blocks = parse_post_blocks(content: content)
        
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0].is_text != nil, true)
    }

    func testHashtagsInQuote() {
        let content = "This is my \"#awesome post\""
        let blocks = parse_post_blocks(content: content)
        
        XCTAssertEqual(blocks.count, 3)
        XCTAssertEqual(blocks[0].is_text, "This is my \"")
        XCTAssertEqual(blocks[1].is_hashtag, "awesome")
        XCTAssertEqual(blocks[2].is_text, " post\"")
    }
    
    func testHashtagAtStartWorks() {
        let content = "#hashtag"
        let blocks = parse_post_blocks(content: content)
        XCTAssertEqual(blocks.count, 3)
        XCTAssertEqual(blocks[1].is_hashtag, "hashtag")
    }
    
    func testGroupOfHashtags() {
        let content = "#hashtag#what#nope"
        let blocks = parse_post_blocks(content: content)
        XCTAssertEqual(blocks.count, 3)
        XCTAssertEqual(blocks[1].is_hashtag, "hashtag")
        XCTAssertEqual(blocks[2].is_text, "#what#nope")
        
        switch blocks[1] {
        case .hashtag(let htag):
            XCTAssertEqual(htag, "hashtag")
        default:
            break
        }
    }
    
    func testRootReplyWithMention() throws {
        let content = "this is #[1] a mention"
        let tags = [["e", "thread_id"], ["e", "mentioned_id"]]
        let blocks = parse_mentions(content: content, tags: tags)
        let event_refs = interpret_event_refs(blocks: blocks, tags: tags)
        
        XCTAssertEqual(event_refs.count, 2)
        XCTAssertNotNil(event_refs[0].is_reply)
        XCTAssertNotNil(event_refs[0].is_thread_id)
        XCTAssertNotNil(event_refs[0].is_reply)
        XCTAssertNotNil(event_refs[0].is_direct_reply)
        XCTAssertEqual(event_refs[0].is_reply!.ref_id, "thread_id")
        XCTAssertEqual(event_refs[0].is_thread_id!.ref_id, "thread_id")
        XCTAssertNotNil(event_refs[1].is_mention)
        XCTAssertEqual(event_refs[1].is_mention!.type, .event)
        XCTAssertEqual(event_refs[1].is_mention!.ref.ref_id, "mentioned_id")
    }
    
    func testEmptyMention() throws {
        let content = "this is some & content"
        let tags: [[String]] = []
        let blocks = parse_mentions(content: content, tags: tags)
        let post_blocks = parse_post_blocks(content: content)
        let post_tags = make_post_tags(post_blocks: post_blocks, tags: tags)
        let event_refs = interpret_event_refs(blocks: blocks, tags: tags)
        
        XCTAssertEqual(event_refs.count, 0)
        XCTAssertEqual(post_tags.blocks.count, 1)
        XCTAssertEqual(post_tags.tags.count, 0)
        XCTAssertEqual(post_blocks.count, 1)
    }
    
    func testManyPostMentions() throws {
        let content = """
@38bc54a8f675564058b987056fc27fe3d40ca34404586933a115d9e0baeaccb9
@774734fad6c318799149c35008c356352b8bfc1791d9e41c803bd412b23143be
@d64266d4bbf3cbcb773d074ee5ffe9ae557425cce0521e102dfde88a7223fb4c
@9f936cfb57374c95c4b8f2d5e640d978e4c59ccbe7783d434f434a8cc69bfa07
@29080a53a6cef22b28dd8c9a25684cb9c2691f8f0c98651d20c65e1a2cd5cef1
@dcdc52ec631c4034b0766a49865ec2e7fc0cdb2ba071aff4050eba343e7ba0fe
@136f15a6e4c5f046a71ddaf014bbca51408041d5d0ec2a0154be4b089e6f0249
@5d994e704a4d3edf0163a708f69cb821f5a9caefeb79c17c1507e11e8a238f36
@d76951e648f1b00715fe55003fcfb6fe91a7bf73fca5b6fd3e5bbe6845a5a0b1
@3e999f94e2cb34ef44a64b351141ac4e51b5121b2d31aed4a6c84602a1144692
"""
        //let tags: [[String]] = []
        let blocks = parse_post_blocks(content: content)
        
        let mentions = blocks.filter { $0.is_ref != nil }
        XCTAssertEqual(mentions.count, 10)
    }
    
    func testManyMentions() throws {
        let content = "#[10]"
        let tags: [[String]] = [[],[],[],[],[],[],[],[],[],[],["p", "3e999f94e2cb34ef44a64b351141ac4e51b5121b2d31aed4a6c84602a1144692"]]
        let blocks = parse_mentions(content: content, tags: tags)
        let mentions = blocks.filter { $0.is_mention }
        XCTAssertEqual(mentions.count, 1)
    }
    
    func testThreadedReply() throws {
        let content = "this is some content"
        let tags = [["e", "thread_id"], ["e", "reply_id"]]
        let blocks = parse_mentions(content: content, tags: tags)
        let event_refs = interpret_event_refs(blocks: blocks, tags: tags)
        
        XCTAssertEqual(event_refs.count, 2)
        let r1 = event_refs[0]
        let r2 = event_refs[1]
        
        XCTAssertEqual(r1.is_thread_id!.ref_id, "thread_id")
        XCTAssertEqual(r2.is_reply!.ref_id, "reply_id")
        XCTAssertEqual(r2.is_direct_reply!.ref_id, "reply_id")
        XCTAssertNil(r1.is_direct_reply)
    }
    
    func testRootReply() throws {
        let content = "this is a reply"
        let tags = [["e", "thread_id"]]
        let blocks = parse_mentions(content: content, tags: tags)
        let event_refs = interpret_event_refs(blocks: blocks, tags: tags)
        
        XCTAssertEqual(event_refs.count, 1)
        let r = event_refs[0]
        
        XCTAssertEqual(r.is_direct_reply!.ref_id, "thread_id")
        XCTAssertEqual(r.is_reply!.ref_id, "thread_id")
        XCTAssertEqual(r.is_thread_id!.ref_id, "thread_id")
        XCTAssertNil(r.is_mention)
    }
    
    func testNoReply() throws {
        let content = "this is a #[0] reply"
        let blocks = parse_mentions(content: content, tags: [])
        let event_refs = interpret_event_refs(blocks: blocks, tags: [])
        
        XCTAssertEqual(event_refs.count, 0)
    }
    
    func testParseMention() throws {
        let parsed = parse_mentions(content: "this is #[0] a mention", tags: [["e", "event_id"]])
        
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed.count, 3)
        XCTAssertEqual(parsed[0].is_text!, "this is ")
        XCTAssertNotNil(parsed[1].is_mention)
        XCTAssertEqual(parsed[2].is_text!, " a mention")
    }
    
    func testEmptyPostReference() throws {
        let parsed = parse_post_blocks(content: "")
        XCTAssertEqual(parsed.count, 0)
    }
    
    func testBech32MentionAtStart() throws {
        let pk = "npub1xtscya34g58tk0z605fvr788k263gsu6cy9x0mhnm87echrgufzsevkk5s"
        let hex_pk = "32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245"
        let content = "@\(pk) hello there"
        let blocks = parse_post_blocks(content: content)
        
        XCTAssertEqual(blocks.count, 3)
        XCTAssertEqual(blocks[0].is_text, "")
        XCTAssertEqual(blocks[1].is_ref, ReferencedId(ref_id: hex_pk, relay_id: nil, key: "p"))
        XCTAssertEqual(blocks[2].is_text, " hello there")
        
    }
    
    func testBech32MentionAtEnd() throws {
        let pk = "npub1xtscya34g58tk0z605fvr788k263gsu6cy9x0mhnm87echrgufzsevkk5s"
        let hex_pk = "32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245"
        let content = "this is a @\(pk)"
        let blocks = parse_post_blocks(content: content)
        
        XCTAssertEqual(blocks.count, 3)
        XCTAssertEqual(blocks[1].is_ref, ReferencedId(ref_id: hex_pk, relay_id: nil, key: "p"))
        XCTAssertEqual(blocks[0].is_text, "this is a ")
        XCTAssertEqual(blocks[2].is_text, "")
        
    }
    
    func testNpubMention() throws {
        let evid = "0000000000000000000000000000000000000000000000000000000000000005"
        let pk = "npub1xtscya34g58tk0z605fvr788k263gsu6cy9x0mhnm87echrgufzsevkk5s"
        let hex_pk = "32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245"
        let content = "this is a @\(pk) mention"
        let reply_ref = ReferencedId(ref_id: evid, relay_id: nil, key: "e")
        let blocks = parse_post_blocks(content: content)
        let post = NostrPost(content: content, references: [reply_ref])
        let ev = post_to_event(post: post, privkey: evid, pubkey: pk)
        
        XCTAssertEqual(ev.tags.count, 2)
        XCTAssertEqual(blocks.count, 3)
        XCTAssertEqual(blocks[1].is_ref, ReferencedId(ref_id: hex_pk, relay_id: nil, key: "p"))
        XCTAssertEqual(ev.content, "this is a #[1] mention")
    }
    
    func testNoteMention() throws {
        let evid = "0000000000000000000000000000000000000000000000000000000000000005"
        let pk = "note154fwmp6hdxqnmqdzkt5jeay8l4kxdsrpn02vw9kp4gylkxxur5fsq3ckpy"
        let hex_note_id = "a552ed875769813d81a2b2e92cf487fd6c66c0619bd4c716c1aa09fb18dc1d13"
        let content = "this is a @\(pk) &\(pk) mention"
        let reply_ref = ReferencedId(ref_id: evid, relay_id: nil, key: "e")
        let blocks = parse_post_blocks(content: content)
        let post = NostrPost(content: content, references: [reply_ref])
        let ev = post_to_event(post: post, privkey: evid, pubkey: pk)
        
        XCTAssertEqual(ev.tags.count, 3)
        XCTAssertEqual(blocks.count, 5)
        XCTAssertEqual(blocks[1].is_ref, ReferencedId(ref_id: hex_note_id, relay_id: nil, key: "e"))
        XCTAssertEqual(blocks[3].is_ref, ReferencedId(ref_id: hex_note_id, relay_id: nil, key: "e"))
        XCTAssertEqual(ev.content, "this is a #[1] #[2] mention")
    }
    
    func testNsecMention() throws {
        let evid = "0000000000000000000000000000000000000000000000000000000000000005"
        let pk = "nsec1jmzdz7d0ldqctdxwm5fzue277ttng2pk28n2u8wntc2r4a0w96ssnyukg7"
        let hex_pk = "ccf95d668650178defca5ac503693b6668eb77895f610178ff8ed9fe5cf9482e"
        let content = "this is a @\(pk) mention"
        let reply_ref = ReferencedId(ref_id: evid, relay_id: nil, key: "e")
        let blocks = parse_post_blocks(content: content)
        let post = NostrPost(content: content, references: [reply_ref])
        let ev = post_to_event(post: post, privkey: evid, pubkey: pk)
        
        XCTAssertEqual(ev.tags.count, 2)
        XCTAssertEqual(blocks.count, 3)
        XCTAssertEqual(blocks[1].is_ref, ReferencedId(ref_id: hex_pk, relay_id: nil, key: "p"))
        XCTAssertEqual(ev.content, "this is a #[1] mention")
    }
    
    func testPostWithMentions() throws {
        let evid = "0000000000000000000000000000000000000000000000000000000000000005"
        let pk = "32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245"
        let content = "this is a @\(pk) mention"
        let reply_ref = ReferencedId(ref_id: evid, relay_id: nil, key: "e")
        let post = NostrPost(content: content, references: [reply_ref])
        let ev = post_to_event(post: post, privkey: evid, pubkey: pk)
        
        XCTAssertEqual(ev.tags.count, 2)
        XCTAssertEqual(ev.content, "this is a #[1] mention")
    }
    
    func testPostTags() throws {
        let pk = "32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245"
        let content = "this is a @\(pk) mention"
        let parsed = parse_post_blocks(content: content)
        let post_tags = make_post_tags(post_blocks: parsed, tags: [])
        
        XCTAssertEqual(post_tags.blocks.count, 3)
        XCTAssertEqual(post_tags.tags.count, 1)
        XCTAssertEqual(post_tags.tags[0].count, 2)
        XCTAssertEqual(post_tags.tags[0][0], "p")
        XCTAssertEqual(post_tags.tags[0][1], pk)
    }
    
    func testReplyMentions() throws {
        let privkey = "0fc2092231f958f8d57d66f5e238bb45b6a2571f44c0ce024bbc6f3a9c8a15fe"
        let pubkey  = "30c6d1dc7f7c156794fa15055e651b758a61b99f50fcf759de59386050bf6ae2"
        
        let refs = [
            ReferencedId(ref_id: "thread_id", relay_id: nil, key: "e"),
            ReferencedId(ref_id: "reply_id", relay_id: nil, key: "e"),
            ReferencedId(ref_id: pubkey, relay_id: nil, key: "p"),
        ]
        
        let post = NostrPost(content: "this is a (@\(pubkey)) mention", references: refs)
        let ev = post_to_event(post: post, privkey: privkey, pubkey: pubkey)
        
        XCTAssertEqual(ev.content, "this is a (#[2]) mention")
        XCTAssertEqual(ev.tags[2][1], pubkey)
    }
    
    func testInvalidPostReference() throws {
        let pk = "32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e24"
        let content = "this is a @\(pk) mention"
        let parsed = parse_post_blocks(content: content)
        XCTAssertEqual(parsed.count, 1)
        guard case .text(let txt) = parsed[0] else {
            XCTAssert(false)
            return
        }
        XCTAssertEqual(txt, content)
    }
    
    func testInvalidPostReferenceEmptyAt() throws {
        let content = "this is a @ mention"
        let parsed = parse_post_blocks(content: content)
        XCTAssertEqual(parsed.count, 1)
        guard case .text(let txt) = parsed[0] else {
            XCTAssert(false)
            return
        }
        XCTAssertEqual(txt, content)
    }
    
    func testFunnyUriReference() throws {
        let id = "6fec2ee6cfff779fe8560976b3d9df782b74577f0caefa7a77c0ed4c3749b5de"
        let content = "this is a nostr:&\(id):\(id) event mention"
        let parsed = parse_post_blocks(content: content)
        
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed.count, 3)
        XCTAssertEqual(parsed[0].is_text, "this is a nostr:")
        XCTAssertTrue(parsed[1].is_ref != nil)
        XCTAssertEqual(parsed[2].is_text, ":\(id) event mention")
        
        guard case .ref(let ref) = parsed[1] else {
            XCTAssertTrue(false)
            return
        }
        XCTAssertEqual(ref.ref_id, id)
        XCTAssertEqual(ref.key, "e")
        XCTAssertNil(ref.relay_id)
        
        guard case .text(let t1) = parsed[0] else {
            XCTAssertTrue(false)
            return
        }
        XCTAssertEqual(t1, "this is a nostr:")
        
        guard case .text(let t2) = parsed[2] else {
            XCTAssertTrue(false)
            return
        }
        XCTAssertEqual(t2, ":\(id) event mention")
    }
    
    func testInvalidUriReference() throws {
        let id = "6fec2ee6cfff779fe8560976b3d9df782b74577f0caefa7a77c0ed4c3749b5de"
        let content = "this is a nostr:z:\(id) event mention"
        let parsed = parse_post_blocks(content: content)
        
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed.count, 1)
        
        guard case .text(let txt) = parsed[0] else {
            XCTAssertTrue(false)
            return
        }
        
        XCTAssertEqual(txt, content)
    }
    
    func testParsePostUriPubkeyReference() throws {
        let id = "6fec2ee6cfff779fe8560976b3d9df782b74577f0caefa7a77c0ed4c3749b5de"
        let parsed = parse_post_blocks(content: "this is a nostr:p:\(id) event mention")
        
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed.count, 3)
        XCTAssertEqual(parsed[0].is_text, "this is a ")
        XCTAssertNotNil(parsed[1].is_ref)
        XCTAssertEqual(parsed[2].is_text, " event mention")
        
        guard case .ref(let ref) = parsed[1] else {
            XCTAssertTrue(false)
            return
        }
        XCTAssertEqual(ref.ref_id, id)
        XCTAssertEqual(ref.key, "p")
        XCTAssertNil(ref.relay_id)
        
        guard case .text(let t1) = parsed[0] else {
            XCTAssertTrue(false)
            return
        }
        XCTAssertEqual(t1, "this is a ")
        
        guard case .text(let t2) = parsed[2] else {
            XCTAssertTrue(false)
            return
        }
        XCTAssertEqual(t2, " event mention")
    }
    
    func testParsePostUriReference() throws {
        let id = "6fec2ee6cfff779fe8560976b3d9df782b74577f0caefa7a77c0ed4c3749b5de"
        let parsed = parse_post_blocks(content: "this is a nostr:e:\(id) event mention")
        
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed.count, 3)
        XCTAssertEqual(parsed[0].is_text, "this is a ")
        XCTAssertNotNil(parsed[1].is_ref)
        XCTAssertEqual(parsed[2].is_text, " event mention")
        
        guard case .ref(let ref) = parsed[1] else {
            XCTAssertTrue(false)
            return
        }
        XCTAssertEqual(ref.ref_id, id)
        XCTAssertEqual(ref.key, "e")
        XCTAssertNil(ref.relay_id)
        
        guard case .text(let t1) = parsed[0] else {
            XCTAssertTrue(false)
            return
        }
        XCTAssertEqual(t1, "this is a ")
        
        guard case .text(let t2) = parsed[2] else {
            XCTAssertTrue(false)
            return
        }
        XCTAssertEqual(t2, " event mention")
    }
    
    func testParsePostEventReference() throws {
        let pk = "6fec2ee6cfff779fe8560976b3d9df782b74577f0caefa7a77c0ed4c3749b5de"
        let parsed = parse_post_blocks(content: "this is a &\(pk) event mention")
        
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed.count, 3)
        XCTAssertEqual(parsed[0].is_text, "this is a ")
        XCTAssertNotNil(parsed[1].is_ref)
        XCTAssertEqual(parsed[2].is_text, " event mention")
        
        guard case .ref(let ref) = parsed[1] else {
            XCTAssertTrue(false)
            return
        }
        XCTAssertEqual(ref.ref_id, pk)
        XCTAssertEqual(ref.key, "e")
        XCTAssertNil(ref.relay_id)
        
        guard case .text(let t1) = parsed[0] else {
            XCTAssertTrue(false)
            return
        }
        XCTAssertEqual(t1, "this is a ")
        
        guard case .text(let t2) = parsed[2] else {
            XCTAssertTrue(false)
            return
        }
        XCTAssertEqual(t2, " event mention")
    }
    
    func testParsePostPubkeyReference() throws {
        let pk = "32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245"
        let parsed = parse_post_blocks(content: "this is a @\(pk) mention")
        
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed.count, 3)
        XCTAssertEqual(parsed[0].is_text, "this is a ")
        XCTAssertNotNil(parsed[1].is_ref)
        XCTAssertEqual(parsed[2].is_text, " mention")
        
        guard case .ref(let ref) = parsed[1] else {
            XCTAssertTrue(false)
            return
        }
        XCTAssertEqual(ref.ref_id, pk)
        XCTAssertEqual(ref.key, "p")
        XCTAssertNil(ref.relay_id)
        
        guard case .text(let t1) = parsed[0] else {
            XCTAssertTrue(false)
            return
        }
        XCTAssertEqual(t1, "this is a ")
        
        guard case .text(let t2) = parsed[2] else {
            XCTAssertTrue(false)
            return
        }
        XCTAssertEqual(t2, " mention")
    }
    
    func testParseInvalidMention() throws {
        let parsed = parse_mentions(content: "this is #[0] a mention", tags: [])
        
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed.count, 1)
        XCTAssertEqual(parsed[0].is_text!, "this is #[0] a mention")
    }
    

}
