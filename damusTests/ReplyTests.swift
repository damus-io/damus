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
        XCTAssertTrue(parsed[0].is_text)
        XCTAssertTrue(parsed[1].is_mention)
        XCTAssertTrue(parsed[2].is_text)
    }
    
    func testEmptyPostReference() throws {
        let parsed = parse_post_blocks(content: "")
        XCTAssertEqual(parsed.count, 0)
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
        XCTAssertTrue(parsed[0].is_text)
        XCTAssertTrue(parsed[1].is_ref)
        XCTAssertTrue(parsed[2].is_text)
        
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
        XCTAssertTrue(parsed[0].is_text)
        XCTAssertTrue(parsed[1].is_ref)
        XCTAssertTrue(parsed[2].is_text)
        
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
        XCTAssertTrue(parsed[0].is_text)
        XCTAssertTrue(parsed[1].is_ref)
        XCTAssertTrue(parsed[2].is_text)
        
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
        XCTAssertTrue(parsed[0].is_text)
        XCTAssertTrue(parsed[1].is_ref)
        XCTAssertTrue(parsed[2].is_text)
        
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
        XCTAssertTrue(parsed[0].is_text)
        XCTAssertTrue(parsed[1].is_ref)
        XCTAssertTrue(parsed[2].is_text)
        
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
        XCTAssertTrue(parsed[0].is_text)
        
        guard case .text(let txt) = parsed[0] else {
            XCTAssertTrue(false)
            return
        }
        
        XCTAssertEqual(txt, "this is #[0] a mention")
    }
    

}
