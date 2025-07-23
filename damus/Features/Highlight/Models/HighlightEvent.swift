//
//  HighlightEvent.swift
//  damus
//
//  Created by eric on 4/22/24.
//

import Foundation

struct HighlightEvent {
    let event: NostrEvent

    var event_ref: String? = nil
    var url_ref: URL? = nil
    var context: String? = nil
    
    // MARK: - Initializers and parsers

    static func parse(from ev: NostrEvent) -> HighlightEvent {
        var highlight = HighlightEvent(event: ev)
        
        var best_url_source: (url: URL, tagged_as_source: Bool)? = nil

        for tag in ev.tags {
            guard tag.count >= 2 else { continue }
            switch tag[0].string() {
            case "e":   highlight.event_ref = tag[1].string()
            case "a":   highlight.event_ref = tag[1].string()
            case "r":
                if tag.count >= 3,
                   tag[2].string() == HighlightSource.TAG_SOURCE_ELEMENT,
                   let url = URL(string: tag[1].string()) {
                    // URL marked as source. Very good candidate
                    best_url_source = (url: url, tagged_as_source: true)
                }
                else if tag.count >= 3 && tag[2].string() != HighlightSource.TAG_SOURCE_ELEMENT {
                    // URL marked as something else (not source). Not the source we are after
                }
                else if let url = URL(string: tag[1].string()), tag.count == 2 {
                    // Unmarked URL. This might be what we are after (For NIP-84 backwards compatibility)
                    if (best_url_source?.tagged_as_source ?? false) == false {
                        // No URL candidates marked as the source. Mark this as the best option we have
                        best_url_source = (url: url, tagged_as_source: false)
                    }
                }
            case "context": highlight.context = tag[1].string()
            default:
                break
            }
        }
        
        if let best_url_source {
            highlight.url_ref = best_url_source.url
        }

        return highlight
    }
    
    // MARK: - Getting information about source
    
    func source_description_info(highlighted_event: NostrEvent?) -> ReplyDesc {
        var others_count = 0
        var highlighted_authors: [Pubkey] = []
        var i = event.tags.count

        if let highlighted_event {
            highlighted_authors.append(highlighted_event.pubkey)
        }

        for tag in event.tags {
            if let pubkey_with_role = PubkeyWithRole.from_tag(tag: tag) {
                others_count += 1
                if highlighted_authors.count < 2 {
                    if let highlighted_event, pubkey_with_role.pubkey == highlighted_event.pubkey {
                        continue
                    } else {
                        switch pubkey_with_role.role {
                            case .author:
                                highlighted_authors.append(pubkey_with_role.pubkey)
                            default:
                                break
                        }
                        
                    }
                }
            }
            i -= 1
        }

        return ReplyDesc(pubkeys: highlighted_authors, others: others_count)
    }
    
    func source_description_text(ndb: Ndb, highlighted_event: NostrEvent?, locale: Locale = Locale.current) -> String {
        let description_info = self.source_description_info(highlighted_event: highlighted_event)
        let pubkeys = description_info.pubkeys

        let bundle = bundleForLocale(locale: locale)

        if pubkeys.count == 0 {
            return NSLocalizedString("Highlighted", bundle: bundle, comment: "Label to indicate that the user is highlighting their own post.")
        }

        guard let profile_txn = NdbTxn(ndb: ndb) else  {
            return ""
        }

        let names: [String] = pubkeys.map { pk in
            let prof = ndb.lookup_profile_with_txn(pk, txn: profile_txn)

            return Profile.displayName(profile: prof?.profile, pubkey: pk).username.truncate(maxLength: 50)
        }

        let uniqueNames: [String] = Array(Set(names))
        return String(format: NSLocalizedString("Highlighted %@", bundle: bundle, comment: "Label to indicate that the user is highlighting 1 user."), locale: locale, uniqueNames.first ?? "")
    }
}

// MARK: - Helper structures

extension HighlightEvent {
    struct PubkeyWithRole: TagKey, TagConvertible {
        let pubkey: Pubkey
        let role: Role

        var tag: [String] {
            if let role_text = self.role.rawValue {
                return [keychar.description, self.pubkey.hex(), role_text]
            }
            else {
                return [keychar.description, self.pubkey.hex()]
            }
        }

        var keychar: AsciiCharacter { "p" }

        static func from_tag(tag: TagSequence) -> HighlightEvent.PubkeyWithRole? {
            var i = tag.makeIterator()
            
            guard tag.count >= 2,
                  let t0 = i.next(),
                  let key = t0.single_char,
                  key == "p",
                  let t1 = i.next(),
                  let pubkey = t1.id().map(Pubkey.init)
            else { return nil }
            
            let t3: String? = i.next()?.string()
            let role = Role(rawValue: t3)
            return PubkeyWithRole(pubkey: pubkey, role: role)
        }
        
        enum Role: RawRepresentable {
            case author
            case editor
            case mention
            case other(String)
            case no_role
            
            typealias RawValue = String?
            var rawValue: String? {
                switch self {
                    case .author: "author"
                    case .editor: "editor"
                    case .mention: "mention"
                    case .other(let role): role
                    case .no_role: nil
                }
            }
            
            init(rawValue: String?) {
                switch rawValue {
                    case "author": self = .author
                    case "editor": self = .editor
                    case "mention": self = .mention
                    default:
                        if let rawValue {
                            self = .other(rawValue)
                        }
                        else {
                            self = .no_role
                        }
                }
            }
        }
    }
}

struct HighlightContentDraft: Hashable {
    let selected_text: String
    let source: HighlightSource
    
    
    init(selected_text: String, source: HighlightSource) {
        self.selected_text = selected_text
        self.source = source
    }
    
    init?(from note: NdbNote) {
        guard let source = HighlightSource.from(tags: note.tags.strings()) else { return nil }
        self.source = source
        self.selected_text = note.content
    }
}

enum HighlightSource: Hashable {
    static let TAG_SOURCE_ELEMENT = "source"
    case event(NoteId)
    case external_url(URL)
    
    func tags() -> [[String]] {
        switch self {
            case .event(let event_id):
                return [ ["e", "\(event_id)", HighlightSource.TAG_SOURCE_ELEMENT] ]
            case .external_url(let url):
                return [ ["r", "\(url)", HighlightSource.TAG_SOURCE_ELEMENT] ]
        }
    }
    
    func ref() -> RefId {
        switch self {
            case .event(let event_id):
                return .event(event_id)
            case .external_url(let url):
                return .reference(url.absoluteString)
        }
    }
    
    static func from(tags: [[String]]) -> HighlightSource? {
        for tag in tags {
            if tag.count == 3 && tag[0] == "e" && tag[2] == HighlightSource.TAG_SOURCE_ELEMENT {
                guard let event_id = NoteId(hex: tag[1]) else { continue }
                return .event(event_id)
            }
            if tag.count == 3 && tag[0] == "r" && tag[2] == HighlightSource.TAG_SOURCE_ELEMENT {
                guard let url = URL(string: tag[1]) else { continue }
                return .external_url(url)
            }
        }
        return nil
    }
}

struct ShareContent {
    let title: String
    let content: ContentType
    
    enum ContentType {
        case link(URL)
        case media([PreUploadedMedia])
    }
    
    func getLinkURL() -> URL? {
        if case let .link(url) = content {
            return url
        }
        return nil
    }
        
    func getMediaArray() -> [PreUploadedMedia] {
        if case let .media(mediaArray) = content {
            return mediaArray
        }
        return []
    }
}
