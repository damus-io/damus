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
        let blocks = parse_note_content(content: content, tags: tags).blocks
        let event_refs = interpret_event_refs(blocks: blocks, tags: tags)
        
        XCTAssertEqual(event_refs.count, 1)
        
        let ref = event_refs[0]
        
        XCTAssertNil(ref.is_reply)
        XCTAssertNil(ref.is_thread_id)
        XCTAssertNil(ref.is_direct_reply)
        XCTAssertEqual(ref.is_mention?.type, .event)
        XCTAssertEqual(ref.is_mention?.ref.ref_id, "event_id")
    }
    
    func testUrlAnchorsAreNotHashtags() {
        let content = "this is my link: https://jb55.com/index.html#buybitcoin this is not a hashtag!"
        let blocks = parse_post_blocks(content: content)
        
        XCTAssertEqual(blocks.count, 3)
        XCTAssertEqual(blocks[0].is_text, "this is my link: ")
        XCTAssertEqual(blocks[1].is_url, URL(string: "https://jb55.com/index.html#buybitcoin")!)
        XCTAssertEqual(blocks[2].is_text, " this is not a hashtag!")
    }

    func testLinkIsNotAHashtag() {
        let link = "https://github.com/damus-io/damus/blob/b7513f28fa1d31c2747865067256ad1d7cf43aac/damus/Nostr/NostrEvent.swift#L560"
        
        let content = "my \(link) link"
        let blocks = parse_post_blocks(content: content)
        
        XCTAssertEqual(blocks.count, 3)
        XCTAssertEqual(blocks[0].is_text, "my ")
        XCTAssertEqual(blocks[1].is_url, URL(string: link)!)
        XCTAssertEqual(blocks[2].is_text, " link")
    }
    
    func testAtAtEnd() {
        let content = "what @"
        let blocks = parse_post_blocks(content: content)
        
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0].is_text, "what @")
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
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0].is_hashtag, "hashtag")
    }
    
    func testGroupOfHashtags() {
        let content = "#hashtag#what#nope"
        let blocks = parse_post_blocks(content: content)
        XCTAssertEqual(blocks.count, 3)
        XCTAssertEqual(blocks[0].is_hashtag, "hashtag")
        XCTAssertEqual(blocks[1].is_hashtag, "what")
        XCTAssertEqual(blocks[2].is_hashtag, "nope")
    }
    
    func testRootReplyWithMention() throws {
        let content = "this is #[1] a mention"
        let tags = [["e", "thread_id"], ["e", "mentioned_id"]]
        let blocks = parse_note_content(content: content, tags: tags).blocks
        let event_refs = interpret_event_refs(blocks: blocks, tags: tags)
        
        XCTAssertEqual(event_refs.count, 2)
        XCTAssertNotNil(event_refs[0].is_reply)
        XCTAssertNotNil(event_refs[0].is_thread_id)
        XCTAssertNotNil(event_refs[0].is_reply)
        XCTAssertNotNil(event_refs[0].is_direct_reply)
        XCTAssertEqual(event_refs[0].is_reply?.ref_id, "thread_id")
        XCTAssertEqual(event_refs[0].is_thread_id?.ref_id, "thread_id")
        XCTAssertNotNil(event_refs[1].is_mention)
        XCTAssertEqual(event_refs[1].is_mention?.type, .event)
        XCTAssertEqual(event_refs[1].is_mention?.ref.ref_id, "mentioned_id")
    }
    
    func testEmptyMention() throws {
        let content = "this is some & content"
        let tags: [[String]] = []
        let blocks = parse_note_content(content: content, tags: tags).blocks
        let post_blocks = parse_post_blocks(content: content)
        let post_tags = make_post_tags(post_blocks: post_blocks, tags: tags)
        let event_refs = interpret_event_refs(blocks: blocks, tags: tags)
        
        XCTAssertEqual(event_refs.count, 0)
        XCTAssertEqual(post_tags.blocks.count, 1)
        XCTAssertEqual(post_tags.tags.count, 0)
        XCTAssertEqual(post_blocks.count, 1)
    }

    func testManyMentions() throws {
        let content = "#[10]"
        let tags: [[String]] = [[],[],[],[],[],[],[],[],[],[],["p", "3e999f94e2cb34ef44a64b351141ac4e51b5121b2d31aed4a6c84602a1144692"]]
        let blocks = parse_note_content(content: content, tags: tags).blocks
        let mentions = blocks.filter { $0.is_mention != nil }
        XCTAssertEqual(mentions.count, 1)
    }

    func testNewlineMentions() throws {
        let pk = "npub1xtscya34g58tk0z605fvr788k263gsu6cy9x0mhnm87echrgufzsevkk5s"
        guard let hex_pk = bech32_pubkey_decode(pk) else {
            return
        }

        let profile = Profile(name: "jb55")
        let post = user_tag_attr_string(profile: profile, pubkey: pk)
        post.append(.init(string: "\n"))
        post.append(user_tag_attr_string(profile: profile, pubkey: pk))
        post.append(.init(string: "\n"))

        let post_note = build_post(post: post, action: .posting(.none), uploadedMedias: [], references: [.p(hex_pk)])

        let expected_render = "nostr:\(pk)\nnostr:\(pk)"
        XCTAssertEqual(post_note.content, expected_render)

        let blocks = parse_note_content(content: post_note.content, tags: []).blocks
        let rendered = render_blocks(blocks: blocks)

        XCTAssertEqual(rendered, expected_render)

        XCTAssertEqual(blocks.count, 3)
        XCTAssertEqual(blocks[0].is_mention, .pubkey(hex_pk))
        XCTAssertEqual(blocks[1].is_text, "\n")
        XCTAssertEqual(blocks[2].is_mention, .pubkey(hex_pk))
    }
    
    func testThreadedReply() throws {
        let content = "this is some content"
        let tags = [["e", "thread_id"], ["e", "reply_id"]]
        let blocks = parse_note_content(content: content, tags: tags).blocks
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
        let blocks = parse_note_content(content: content, tags: tags).blocks
        let event_refs = interpret_event_refs(blocks: blocks, tags: tags)
        
        XCTAssertEqual(event_refs.count, 1)
        let r = event_refs[0]
        
        XCTAssertEqual(r.is_direct_reply!.ref_id, "thread_id")
        XCTAssertEqual(r.is_reply!.ref_id, "thread_id")
        XCTAssertEqual(r.is_thread_id!.ref_id, "thread_id")
        XCTAssertNil(r.is_mention)
    }

    func testAdjacentComposedMention() throws {
        let content = "cc@jb55"

        let profile = Profile(name: "jb55")
        let tag = user_tag_attr_string(profile: profile, pubkey: "pk")
        let appended = append_user_tag(tag: tag, post: .init(string: content), word_range: .init(2...6))
        let new_post = appended.post

        try new_post.testAttributes(conditions: [
            { let link = $0[.link] as? String; XCTAssertNil(link) },
            { let link = $0[.link] as! String; XCTAssertEqual(link, "damus:nostr:pk") },
            { let link = $0[.link] as? String; XCTAssertNil(link) }
        ])

        XCTAssertEqual(new_post.string, "cc @jb55 ")
    }

    func testAdjacentEmojiComposedMention() throws {
        let content = "😎@jb55"

        let profile = Profile(name: "jb55")
        let tag = user_tag_attr_string(profile: profile, pubkey: "pk")
        let appended = append_user_tag(tag: tag, post: .init(string: content), word_range: .init(2...6))
        let new_post = appended.post

        try new_post.testAttributes(conditions: [
            { let link = $0[.link] as? String; XCTAssertNil(link) },
            { let link = $0[.link] as! String; XCTAssertEqual(link, "damus:nostr:pk") },
            { let link = $0[.link] as? String; XCTAssertNil(link) }
        ])

        XCTAssertEqual(new_post.string, "😎 @jb55 ")
    }

    func testComposedMentionNewline() throws {
        let content = """
        
        @jb55
        """

        let profile = Profile(name: "jb55")
        let tag = user_tag_attr_string(profile: profile, pubkey: "pk")
        let appended = append_user_tag(tag: tag, post: .init(string: content), word_range: .init(1...5))
        let new_post = appended.post

        try new_post.testAttributes(conditions: [
            { let link = $0[.link] as? String; XCTAssertNil(link) },
            { let link = $0[.link] as! String; XCTAssertEqual(link, "damus:nostr:pk") },
            { let link = $0[.link] as? String; XCTAssertNil(link) },
        ])

        XCTAssertEqual(new_post.string, "\n@jb55 ")
    }

    func testComposedMention() throws {
        let content = "@jb55"

        let profile = Profile(name: "jb55")
        let tag = user_tag_attr_string(profile: profile, pubkey: "pk")
        let appended = append_user_tag(tag: tag, post: .init(string: content), word_range: .init(0...4))
        let new_post = appended.post

        try new_post.testAttributes(conditions: [
            { let link = $0[.link] as! String; XCTAssertEqual(link, "damus:nostr:pk") },
            { let link = $0[.link] as? String; XCTAssertNil(link) },
        ])

        XCTAssertEqual(new_post.string, "@jb55 ")
    }

    func testAdjacentSpaceComposedMention() throws {
        let content = "cc @jb55"

        let profile = Profile(name: "jb55")
        let tag = user_tag_attr_string(profile: profile, pubkey: "pk")
        let appended = append_user_tag(tag: tag, post: .init(string: content), word_range: .init(3...7))
        let new_post = appended.post

        try new_post.testAttributes(conditions: [
            { let link = $0[.link] as? String; XCTAssertNil(link) },
            { let link = $0[.link] as! String; XCTAssertEqual(link, "damus:nostr:pk") },
            { let link = $0[.link] as? String; XCTAssertNil(link) }
        ])

        XCTAssertEqual(new_post.string, "cc @jb55 ")
    }

    func testNoReply() throws {
        let content = "this is a #[0] reply"
        let blocks = parse_note_content(content: content, tags: []).blocks
        let event_refs = interpret_event_refs(blocks: blocks, tags: [])
        
        XCTAssertEqual(event_refs.count, 0)
    }
    
    func testParseMention() throws {
        let parsed = parse_note_content(content: "this is #[0] a mention", tags: [["e", "event_id"]]).blocks
        
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed.count, 3)
        XCTAssertEqual(parsed[0].is_text, "this is ")
        XCTAssertNotNil(parsed[1].is_mention)
        XCTAssertEqual(parsed[2].is_text, " a mention")
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
        
        XCTAssertEqual(blocks.count, 2)
        XCTAssertEqual(blocks[0].is_mention, .pubkey(hex_pk))
        XCTAssertEqual(blocks[1].is_text, " hello there")

    }
    
    func testBech32MentionAtEnd() throws {
        let pk = "npub1xtscya34g58tk0z605fvr788k263gsu6cy9x0mhnm87echrgufzsevkk5s"
        let hex_pk = "32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245"
        let content = "this is a @\(pk)"
        let blocks = parse_post_blocks(content: content)
        
        XCTAssertEqual(blocks.count, 2)
        XCTAssertEqual(blocks[1].is_mention, .pubkey(hex_pk))
        XCTAssertEqual(blocks[0].is_text, "this is a ")
    }
    
    func testNpubMention() throws {
        let evid = "0000000000000000000000000000000000000000000000000000000000000005"
        let pk = "npub1xtscya34g58tk0z605fvr788k263gsu6cy9x0mhnm87echrgufzsevkk5s"
        let hex_pk = "32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245"
        let content = "this is a @\(pk) mention"
        let reply_ref = ReferencedId(ref_id: evid, relay_id: nil, key: "e")
        let blocks = parse_post_blocks(content: content)
        let post = NostrPost(content: content, references: [reply_ref])
        let ev = post_to_event(post: post, keypair: test_keypair_full)!

        XCTAssertEqual(ev.tags.count, 2)
        XCTAssertEqual(blocks.count, 3)
        XCTAssertEqual(blocks[1].is_mention, .pubkey(hex_pk))
        XCTAssertEqual(ev.content, "this is a nostr:npub1xtscya34g58tk0z605fvr788k263gsu6cy9x0mhnm87echrgufzsevkk5s mention")
    }
    
    func testNsecMention() throws {
        let evid = "0000000000000000000000000000000000000000000000000000000000000005"
        let pk = "nsec1jmzdz7d0ldqctdxwm5fzue277ttng2pk28n2u8wntc2r4a0w96ssnyukg7"
        let hex_pk = "ccf95d668650178defca5ac503693b6668eb77895f610178ff8ed9fe5cf9482e"
        let content = "this is a @\(pk) mention"
        let reply_ref = ReferencedId(ref_id: evid, relay_id: nil, key: "e")
        let blocks = parse_post_blocks(content: content)
        let post = NostrPost(content: content, references: [reply_ref])
        let ev = post_to_event(post: post, keypair: test_keypair_full)!

        XCTAssertEqual(ev.tags.count, 2)
        XCTAssertEqual(blocks.count, 3)
        XCTAssertEqual(blocks[1].is_mention, .pubkey(hex_pk))
        XCTAssertEqual(ev.content, "this is a nostr:npub1enu46e5x2qtcmm72ttzsx6fmve5wkauftassz78l3mvluh8efqhqejf3v4 mention")
    }
    
    func testReplyMentions() throws {
        let privkey = "0fc2092231f958f8d57d66f5e238bb45b6a2571f44c0ce024bbc6f3a9c8a15fe"
        let pubkey  = "30c6d1dc7f7c156794fa15055e651b758a61b99f50fcf759de59386050bf6ae2"
        let npub =    "npub1xrrdrhrl0s2k0986z5z4uegmwk9xrwvl2r70wkw7tyuxq59ldt3qh09eay"

        let refs = [
            ReferencedId(ref_id: "thread_id", relay_id: nil, key: "e"),
            ReferencedId(ref_id: "reply_id", relay_id: nil, key: "e"),
            ReferencedId(ref_id: pubkey, relay_id: nil, key: "p"),
        ]
        
        let post = NostrPost(content: "this is a (@\(npub)) mention", references: refs)
        let ev = post_to_event(post: post, keypair: test_keypair_full)!
        
        XCTAssertEqual(ev.content, "this is a (nostr:\(npub)) mention")
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
        let npub = try XCTUnwrap(bech32_pubkey(id))
        let parsed = parse_post_blocks(content: "this is a nostr:\(npub) event mention")
        
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed.count, 3)
        XCTAssertEqual(parsed[0].is_text, "this is a ")
        XCTAssertEqual(parsed[1].is_mention, .pubkey(id))
        XCTAssertEqual(parsed[2].is_text, " event mention")
        
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
        let note_id = try XCTUnwrap(bech32_note_id(id))
        let parsed = parse_post_blocks(content: "this is a nostr:\(note_id) event mention")
        
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed.count, 3)
        XCTAssertEqual(parsed[0].is_text, "this is a ")
        XCTAssertEqual(parsed[1].is_mention, .note(id))
        XCTAssertEqual(parsed[2].is_text, " event mention")

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
    
    func testParseInvalidMention() throws {
        let parsed = parse_note_content(content: "this is #[0] a mention", tags: []).blocks
        
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed.count, 3)
        XCTAssertEqual(parsed[0].is_text, "this is ")
        XCTAssertEqual(parsed[1].is_text, "#[0]")
        XCTAssertEqual(parsed[2].is_text, " a mention")
    }

}
