//
//  Post.swift
//  damus
//
//  Created by William Casarin on 2022-05-07.
//

import Foundation

struct NostrPost {
    let kind: NostrKind
    let content: String
    let tags: [[String]]

    init(content: String, kind: NostrKind = .text, tags: [[String]] = []) {
        self.content = content
        self.kind = kind
        self.tags = tags
    }
    
    func to_event(keypair: FullKeypair) -> NostrEvent? {
        let post_blocks = self.parse_blocks()
        let post_tags = self.make_post_tags(post_blocks: post_blocks, tags: self.tags)
        let content = post_tags.blocks
            .map(\.asString)
            .joined(separator: "")
        
        if self.kind == .highlight {
            var new_tags = post_tags.tags.filter({ $0[safe: 0] != "comment" })
            if content.count > 0 {
                new_tags.append(["comment", content])
            }
            return NostrEvent(content: self.content, keypair: keypair.to_keypair(), kind: self.kind.rawValue, tags: new_tags)
        }
        
        return NostrEvent(content: content, keypair: keypair.to_keypair(), kind: self.kind.rawValue, tags: post_tags.tags)
    }
    
    func parse_blocks() -> [Block] {
        guard let content_for_parsing = self.default_content_for_block_parsing() else { return [] }
        return parse_post_blocks(content: content_for_parsing)
    }
    
    private func default_content_for_block_parsing() -> String? {
        switch kind {
            case .highlight:
                return tags.filter({ $0[safe: 0] == "comment" }).first?[safe: 1]
            default:
                return self.content
        }
    }
    
    /// Parse the post's contents to find more tags to apply to the final nostr event
    func make_post_tags(post_blocks: [Block], tags: [[String]]) -> PostTags {
        var new_tags = tags

        for post_block in post_blocks {
            switch post_block {
                case .mention(let mention):
                    switch(mention.ref) {
                    case .note, .nevent:
                        continue
                    default:
                        break
                    }
                    
                    if self.kind == .highlight, case .pubkey(_) = mention.ref {
                        var new_tag = mention.ref.tag
                        new_tag.append("mention")
                        new_tags.append(new_tag)
                    }
                    else {
                        new_tags.append(mention.ref.tag)
                    }
                case .hashtag(let hashtag):
                    new_tags.append(["t", hashtag.lowercased()])
                case .text: break
                case .invoice: break
                case .relay: break
                case .url(let url):
                    new_tags.append(self.kind == .highlight ? ["r", url.absoluteString, "mention"] : ["r", url.absoluteString])
                    break
            }
        }
        
        return PostTags(blocks: post_blocks, tags: new_tags)
    }
}

// MARK: - Helper structures and functions

extension NostrPost {
    /// A struct used for temporarily holding tag information that was parsed from a post contents to aid in building a nostr event
    struct PostTags {
        let blocks: [Block]
        let tags: [[String]]
    }
}

/// Return a list of tags
func parse_post_blocks(content: String) -> Blocks? {
    let buf_size = 16000
    var buffer = Data(capacity: buf_size)
    var blocks_ptr = ndb_blocks_ptr()
    var ok = false

    return content.withCString { c_content -> Blocks? in
        buffer.withUnsafeMutableBytes { buf in
            let res = ndb_parse_content(buf, Int32(buf_size), c_content, Int32(content.utf8.count), &blocks_ptr.ptr)
            ok = res != 0
        }

        guard ok else { return nil }

        let words = ndb_blocks_word_count(blocks_ptr.ptr)
        let bs = collect_blocks(ptr: blocks_ptr, content: c_content)
        return Blocks(words: Int(words), blocks: bs)
    }
}


fileprivate func collect_blocks(ptr: ndb_blocks_ptr, content: UnsafePointer<CChar>) -> [Block] {
    var i = ndb_block_iterator()
    var blocks: [Block] = []
    var block_ptr = ndb_block_ptr()

    ndb_blocks_iterate_start(content, ptr.ptr, &i);
    block_ptr.ptr = ndb_blocks_iterate_next(&i)
    while (block_ptr.ptr != nil) {
        // tags are only used for indexed mentions which aren't used in
        // posts anymore, so to simplify the API let's set this to nil
        if let block = Block(block: block_ptr, tags: nil) {
            blocks.append(block);
        }
        block_ptr.ptr = ndb_blocks_iterate_next(&i)
    }

    return blocks
}
