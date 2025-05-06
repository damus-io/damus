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
    
    return .separated(render_blocks(blocks: blocks, profiles: profiles, can_hide_last_previewable_refs: true))
}

func render_blocks(blocks bs: Blocks, profiles: Profiles, can_hide_last_previewable_refs: Bool = false) -> NoteArtifactsSeparated {
    var invoices: [Invoice] = []
    var urls: [UrlType] = []
    let blocks = bs.blocks

    var end_mention_count = 0
    var end_url_count = 0

    // Search backwards until we find the beginning index of the chain of previewables that reach the end of the content.
    var hide_text_index = blocks.endIndex
    if can_hide_last_previewable_refs {
        outerLoop: for (i, block) in blocks.enumerated().reversed() {
            if block.is_previewable {
                switch block {
                case .mention:
                    end_mention_count += 1

                    // If there is more than one previewable mention,
                    // do not hide anything because we allow rich rendering of only one mention currently.
                    // This should be fixed in the future to show events inline instead.
                    if end_mention_count > 1 {
                        hide_text_index = blocks.endIndex
                        break outerLoop
                    }
                case .url(let url):
                    let url_type = classify_url(url)
                    if case .link = url_type {
                        end_url_count += 1

                        // If there is more than one link, do not hide anything because we allow rich rendering of only
                        // one link.
                        if end_url_count > 1 {
                            hide_text_index = blocks.endIndex
                            break outerLoop
                        }
                    }
                default:
                    break
                }
                hide_text_index = i
            } else if case .text(let txt) = block, txt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                hide_text_index = i
            } else {
                break
            }
        }
    }

    var ind: Int = -1
    let txt: CompatibleText = blocks.reduce(CompatibleText()) { str, block in
        ind = ind + 1

        // Add the rendered previewable blocks to their type-specific lists.
        switch block {
        case .invoice(let invoice):
            invoices.append(invoice)
        case .url(let url):
            let url_type = classify_url(url)
            urls.append(url_type)
        default:
            break
        }

        if can_hide_last_previewable_refs {
            // If there are previewable blocks that occur before the consecutive sequence of them at the end of the content,
            // we should not hide the text representation of any previewable block to avoid altering the format of the note.
            if ind < hide_text_index && block.is_previewable {
                hide_text_index = blocks.endIndex
            }

            // No need to show the text representation of the block if the only previewables are the sequence of them
            // found at the end of the content.
            // This is to save unnecessary use of screen space.
            if ind >= hide_text_index {
                return str
            }
        }

        switch block {
        case .mention(let m):
            return str + mention_str(m, profiles: profiles)
        case .text(let txt):
            return str + CompatibleText(stringLiteral: reduce_text_block(ind: ind, hide_text_index: hide_text_index, txt: txt))
        case .relay(let relay):
            return str + CompatibleText(stringLiteral: relay)
        case .hashtag(let htag):
            return str + hashtag_str(htag)
        case .invoice(let invoice):
            return str + invoice_str(invoice)
        case .url(let url):
            return str + url_str(url)
        }
    }

    return NoteArtifactsSeparated(content: txt, words: bs.words, urls: urls, invoices: invoices)
}

func reduce_text_block(ind: Int, hide_text_index: Int, txt: String) -> String {
    var trimmed = txt

    // Trim leading whitespaces.
    if ind == 0 {
        trimmed = trim_prefix(trimmed)
    }

    // Trim trailing whitespaces if the following blocks will be hidden or if this is the last block.
    if ind == hide_text_index - 1 {
        trimmed = trim_suffix(trimmed)
    }

    return trimmed
}

func invoice_str(_ invoice: Invoice) -> CompatibleText {
    var attributedString = AttributedString(stringLiteral: abbrev_identifier(invoice.string))
    attributedString.link = URL(string: "damus:lightning:\(invoice.string)")
    attributedString.foregroundColor = DamusColors.purple

    return CompatibleText(attributed: attributedString)
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
        switch m.ref {
        case .pubkey(let pk): return getDisplayName(pk: pk, profiles: profiles)
        case .note: return abbrev_identifier(bech32String)
        case .nevent: return abbrev_identifier(bech32String)
        case .nprofile(let nprofile): return getDisplayName(pk: nprofile.author, profiles: profiles)
        case .nrelay(let url): return url
        case .naddr: return abbrev_identifier(bech32String)
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
