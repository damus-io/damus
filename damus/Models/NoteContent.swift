//
//  NoteContent.swift
//  damus
//
//  Created by Daniel D’Aquino on 2023-11-24.
//

import Foundation
import MarkdownUI
import UIKit

struct NoteArtifactsSeparated: Equatable {
    static func == (lhs: NoteArtifactsSeparated, rhs: NoteArtifactsSeparated) -> Bool {
        return lhs.content == rhs.content
    }
    
    let content: CompatibleText
    let words: Int
    let urls: [UrlType]
    let invoices: [Invoice]
    
    var media: [MediaUrl] {
        return urls.compactMap { url in url.is_media }
    }
    
    var images: [URL] {
        return urls.compactMap { url in url.is_img }
    }
    
    var links: [URL] {
        return urls.compactMap { url in url.is_link }
    }
    
    static func just_content(_ content: String) -> NoteArtifactsSeparated {
        let txt = CompatibleText(attributed: AttributedString(stringLiteral: content))
        return NoteArtifactsSeparated(content: txt, words: 0, urls: [], invoices: [])
    }
}

enum NoteArtifactState {
    case not_loaded
    case loading
    case loaded(NoteArtifacts)
    
    var artifacts: NoteArtifacts? {
        if case .loaded(let artifacts) = self {
            return artifacts
        }
        
        return nil
    }
    
    var should_preload: Bool {
        switch self {
        case .loaded:
            return false
        case .loading:
            return false
        case .not_loaded:
            return true
        }
    }
}

func note_artifact_is_separated(kind: NostrKind?) -> Bool {
    return kind != .longform
}

func render_note_content(ev: NostrEvent, profiles: Profiles, keypair: Keypair) -> NoteArtifacts {
    let blocks = ev.blocks(keypair)

    if ev.known_kind == .longform {
        return .longform(LongformContent(ev.content))
    }
    
    return .separated(render_blocks(blocks: blocks, profiles: profiles))
}

func render_blocks(blocks bs: Blocks, profiles: Profiles) -> NoteArtifactsSeparated {
    var invoices: [Invoice] = []
    var urls: [UrlType] = []
    let blocks = bs.blocks
    
    let one_note_ref = blocks
        .filter({
            if case .mention(let mention) = $0,
               case .note = mention.ref {
                return true
            }
            else {
                return false
            }
        })
        .count == 1
    
    var ind: Int = -1
    let txt: CompatibleText = blocks.reduce(CompatibleText()) { str, block in
        ind = ind + 1
        
        switch block {
        case .mention(let m):
            if case .note = m.ref, one_note_ref {
                return str
            }
            return str + mention_str(m, profiles: profiles)
        case .text(let txt):
            return str + CompatibleText(stringLiteral: reduce_text_block(blocks: blocks, ind: ind, txt: txt, one_note_ref: one_note_ref))

        case .relay(let relay):
            return str + CompatibleText(stringLiteral: relay)
            
        case .hashtag(let htag):
            return str + hashtag_str(htag)
        case .invoice(let invoice):
            invoices.append(invoice)
            return str
        case .url(let url):
            let url_type = classify_url(url)
            switch url_type {
            case .media:
                urls.append(url_type)
                return str
            case .link(let url):
                urls.append(url_type)
                return str + url_str(url)
            }
        }
    }

    return NoteArtifactsSeparated(content: txt, words: bs.words, urls: urls, invoices: invoices)
}

func reduce_text_block(blocks: [Block], ind: Int, txt: String, one_note_ref: Bool) -> String {
    var trimmed = txt
    
    if let prev = blocks[safe: ind-1],
       case .url(let u) = prev,
       classify_url(u).is_media != nil {
        trimmed = " " + trim_prefix(trimmed)
    }
    
    if let next = blocks[safe: ind+1] {
        if case .url(let u) = next, classify_url(u).is_media != nil {
            trimmed = trim_suffix(trimmed)
        } else if case .mention(let m) = next,
                  case .note = m.ref,
                  one_note_ref {
            trimmed = trim_suffix(trimmed)
        }
    }
    
    return trimmed
}

func url_str(_ url: URL) -> CompatibleText {
    var attributedString = AttributedString(stringLiteral: url.absoluteString)
    attributedString.link = url
    attributedString.foregroundColor = DamusColors.purple
    
    return CompatibleText(attributed: attributedString)
}

func classify_url(_ url: URL) -> UrlType {
    let str = url.lastPathComponent.lowercased()
    
    if str.hasSuffix(".png") || str.hasSuffix(".jpg") || str.hasSuffix(".jpeg") || str.hasSuffix(".gif") || str.hasSuffix(".webp") {
        return .media(.image(url))
    }
    
    if str.hasSuffix(".mp4") || str.hasSuffix(".mov") || str.hasSuffix(".m3u8") {
        return .media(.video(url))
    }
    
    return .link(url)
}

func attributed_string_attach_icon(_ astr: inout AttributedString, img: UIImage) {
    let attachment = NSTextAttachment()
    attachment.image = img
    let attachmentString = NSAttributedString(attachment: attachment)
    let wrapped = AttributedString(attachmentString)
    astr.append(wrapped)
}

func mention_str(_ m: Mention<MentionRef>, profiles: Profiles) -> CompatibleText {
    switch m.ref {
    case .pubkey(let pk):
        let npub = bech32_pubkey(pk)
        let profile_txn = profiles.lookup(id: pk)
        let profile = profile_txn.unsafeUnownedValue
        let disp = Profile.displayName(profile: profile, pubkey: pk).username.truncate(maxLength: 50)
        var attributedString = AttributedString(stringLiteral: "@\(disp)")
        attributedString.link = URL(string: "damus:nostr:\(npub)")
        attributedString.foregroundColor = DamusColors.purple
        
        return CompatibleText(attributed: attributedString)
    case .note(let note_id):
        let bevid = bech32_note_id(note_id)
        var attributedString = AttributedString(stringLiteral: "@\(abbrev_pubkey(bevid))")
        attributedString.link = URL(string: "damus:nostr:\(bevid)")
        attributedString.foregroundColor = DamusColors.purple

        return CompatibleText(attributed: attributedString)
    }
}

// trim suffix whitespace and newlines
func trim_suffix(_ str: String) -> String {
    return str.replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression)
}

// trim prefix whitespace and newlines
func trim_prefix(_ str: String) -> String {
    return str.replacingOccurrences(of: "^\\s+", with: "", options: .regularExpression)
}

struct LongformContent {
    let markdown: MarkdownContent
    let words: Int

    init(_ markdown: String) {
        let blocks = [BlockNode].init(markdown: markdown)
        self.markdown = MarkdownContent(blocks: blocks)
        self.words = count_markdown_words(blocks: blocks)
    }
}

func count_markdown_words(blocks: [BlockNode]) -> Int {
    return blocks.reduce(0) { words, block in
        switch block {
        case .paragraph(let content):
            return words + count_inline_nodes_words(nodes: content)
        case .blockquote, .bulletedList, .numberedList, .taskList, .codeBlock, .htmlBlock, .heading, .table, .thematicBreak:
            return words
        }
    }
}

func count_words(_ s: String) -> Int {
    return s.components(separatedBy: .whitespacesAndNewlines).count
}

func count_inline_nodes_words(nodes: [InlineNode]) -> Int {
    return nodes.reduce(0) { words, node in
        switch node {
        case .text(let words):
            return count_words(words)
        case .emphasis(let children):
            return words + count_inline_nodes_words(nodes: children)
        case .strong(let children):
            return words + count_inline_nodes_words(nodes: children)
        case .strikethrough(let children):
            return words + count_inline_nodes_words(nodes: children)
        case .softBreak, .lineBreak, .code, .html, .image, .link:
            return words
        }
    }
}

enum NoteArtifacts {
    case separated(NoteArtifactsSeparated)
    case longform(LongformContent)

    var images: [URL] {
        switch self {
        case .separated(let arts):
            return arts.images
        case .longform:
            return []
        }
    }
}

enum UrlType {
    case media(MediaUrl)
    case link(URL)
    
    var url: URL {
        switch self {
        case .media(let media_url):
            switch media_url {
            case .image(let url):
                return url
            case .video(let url):
                return url
            }
        case .link(let url):
            return url
        }
    }
    
    var is_video: URL? {
        switch self {
        case .media(let media_url):
            switch media_url {
            case .image:
                return nil
            case .video(let url):
                return url
            }
        case .link:
            return nil
        }
    }
    
    var is_img: URL? {
        switch self {
        case .media(let media_url):
            switch media_url {
            case .image(let url):
                return url
            case .video:
                return nil
            }
        case .link:
            return nil
        }
    }
    
    var is_link: URL? {
        switch self {
        case .media:
            return nil
        case .link(let url):
            return url
        }
    }
    
    var is_media: MediaUrl? {
        switch self {
        case .media(let murl):
            return murl
        case .link:
            return nil
        }
    }
}

enum MediaUrl {
    case image(URL)
    case video(URL)
    
    var url: URL {
        switch self {
        case .image(let url):
            return url
        case .video(let url):
            return url
        }
    }
}
