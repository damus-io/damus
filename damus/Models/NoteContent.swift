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

func render_note_content(ndb: Ndb, ev: NostrEvent, profiles: Profiles, keypair: Keypair) -> NoteArtifacts {
    guard let blocks = ev.blocks(ndb: ndb) else {
        return .separated(.just_content(ev.get_content(keypair)))
    }

    if ev.known_kind == .longform {
        return .longform(LongformContent(ev.content))
    }
    
    return .separated(render_blocks(blocks: blocks.unsafeUnownedValue, profiles: profiles, note: ev))
}

func render_blocks(blocks: NdbBlocks, profiles: Profiles, note: NdbNote) -> NoteArtifactsSeparated {
    var invoices: [Invoice] = []
    var urls: [UrlType] = []

    let ndb_blocks = blocks.iter(note: note).collect()
    let one_note_ref = ndb_blocks
        .filter({
            if case .mention(let mention) = $0,
               let typ = mention.bech32_type,
               typ.is_notelike {
                return true
            }
            else {
                return false
            }
        })
        .count == 1
    
    var ind: Int = -1
    let txt: CompatibleText = ndb_blocks.reduce(into: CompatibleText()) { str, block in
        ind = ind + 1
        
        switch block {
        case .mention(let m):
            if let typ = m.bech32_type, typ.is_notelike, one_note_ref {
                return
            }
            guard let mention = MentionRef(block: m) else { return }
            str = str + mention_str(.any(mention), profiles: profiles)
        case .text(let txt):
            str = str + CompatibleText(stringLiteral: reduce_text_block(blocks: ndb_blocks, ind: ind, txt: txt.as_str(), one_note_ref: one_note_ref))
        case .hashtag(let htag):
            str = str + hashtag_str(htag.as_str())
        case .invoice(let invoice):
            guard let inv = invoice.as_invoice() else { return }
            invoices.append(inv)
        case .url(let url):
            guard let url = URL(string: url.as_str()) else { return }
            let url_type = classify_url(url)
            switch url_type {
            case .media:
                urls.append(url_type)
            case .link(let url):
                urls.append(url_type)
                str = str + url_str(url)
            }
        case .mention_index:
            return
        }
    }

    return NoteArtifactsSeparated(content: txt, words: blocks.words, urls: urls, invoices: invoices)
}

func reduce_text_block(blocks: [NdbBlock], ind: Int, txt: String, one_note_ref: Bool) -> String {
    var trimmed = txt
    
    if let prev = blocks[safe: ind-1],
       case .url(let u) = prev,
       let url = URL(string: u.as_str()),
       classify_url(url).is_media != nil
    {
        trimmed = " " + trim_prefix(trimmed)
    }
    
    if let next = blocks[safe: ind+1] {
        if case .url(let u) = next,
           let url = URL(string: u.as_str()),
           classify_url(url).is_media != nil
        {
            trimmed = trim_suffix(trimmed)
        } else if case .mention(let m) = next,
                  let typ = m.bech32_type,
                  typ.is_notelike,
                  one_note_ref
        {
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

func getDisplayName(pk: Pubkey, profiles: Profiles) -> String {
    let profile_txn = profiles.lookup(id: pk, txn_name: "getDisplayName")
    let profile = profile_txn?.unsafeUnownedValue
    return Profile.displayName(profile: profile, pubkey: pk).username.truncate(maxLength: 50)
}

func mention_str(_ m: Mention<MentionRef>, profiles: Profiles) -> CompatibleText {
    let bech32String = Bech32Object.encode(m.ref.toBech32Object())
    
    let display_str: String = {
        switch m.ref.nip19 {
        case .npub(let pk): return getDisplayName(pk: pk, profiles: profiles)
        case .note: return abbrev_pubkey(bech32String)
        case .nevent: return abbrev_pubkey(bech32String)
        case .nprofile(let nprofile): return getDisplayName(pk: nprofile.author, profiles: profiles)
        case .nrelay(let url): return url
        case .naddr: return abbrev_pubkey(bech32String)
        case .nsec(let prv): 
            guard let npub = privkey_to_pubkey(privkey: prv)?.npub else { return "nsec..." }
            return abbrev_pubkey(npub)
        case .nscript(_): return bech32String
        }
    }()

    let display_str_with_at = "@\(display_str)"

    var attributedString = AttributedString(stringLiteral: display_str_with_at)
    attributedString.link = URL(string: "damus:nostr:\(bech32String)")
    attributedString.foregroundColor = DamusColors.purple
    
    return CompatibleText(attributed: attributedString)
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
