//
//  MuteItem.swift
//  damus
//
//  Created by Charlie Fish on 1/13/24.
//

import Foundation

/// Represents an item that is muted.
enum MuteItem: Hashable, Equatable {
    /// A user that is muted.
    ///
    /// The associated type is the ``Pubkey`` that is muted. The second associated type is the date that the item should expire at. If no date is supplied, assume the muted item should remain active until it expires.
    case user(Pubkey, Date?)

    /// A hashtag that is muted.
    ///
    /// The associated type is the hashtag string that is muted. The second associated type is the date that the item should expire at. If no date is supplied, assume the muted item should remain active until it expires.
    case hashtag(Hashtag, Date?)

    /// A word/phrase that is muted.
    ///
    /// The associated type is the word/phrase that is muted. The second associated type is the date that the item should expire at. If no date is supplied, assume the muted item should remain active until it expires.
    case word(String, Date?)

    /// A thread that is muted.
    ///
    /// The associated type is the `id` of the note that is muted. The second associated type is the date that the item should expire at. If no date is supplied, assume the muted item should remain active until it expires.
    case thread(NoteId, Date?)

    func is_expired() -> Bool {
        switch self {
        case .user(_, let expiration_date):
            return expiration_date ?? .distantFuture < Date()
        case .hashtag(_, let expiration_date):
            return expiration_date ?? .distantFuture < Date()
        case .word(_, let expiration_date):
            return expiration_date ?? .distantFuture < Date()
        case .thread(_, let expiration_date):
            return expiration_date ?? .distantFuture < Date()
        }
    }

    static func == (lhs: MuteItem, rhs: MuteItem) -> Bool {
        // lhs is the item we want to check (ie. the item the user is attempting to display)
        // rhs is the item we want to check against (ie. the item in the mute list)

        switch (lhs, rhs) {
            case (.user(let lhs_pubkey, _), .user(let rhs_pubkey, let rhs_expiration_date)):
                return lhs_pubkey == rhs_pubkey && !rhs.is_expired()
            case (.hashtag(let lhs_hashtag, _), .hashtag(let rhs_hashtag, let rhs_expiration_date)):
                return lhs_hashtag == rhs_hashtag && !rhs.is_expired()
            case (.word(let lhs_word, _), .word(let rhs_word, let rhs_expiration_date)):
                return lhs_word == rhs_word && !rhs.is_expired()
            case (.thread(let lhs_thread, _), .thread(let rhs_thread, let rhs_expiration_date)):
                return lhs_thread == rhs_thread && !rhs.is_expired()
            default:
                return false
        }
    }

    private var refTags: [String] {
        switch self {
        case .user(let pubkey, _):
            return RefId.pubkey(pubkey).tag
        case .hashtag(let hashtag, _):
            return RefId.hashtag(hashtag).tag
        case .word(let string, _):
            return ["word", string]
        case .thread(let noteId, _):
            return RefId.event(noteId).tag
        }
    }

    var tag: [String] {
        var tag = self.refTags

        switch self {
        case .user(_, let date):
            if let date {
                tag.append("\(Int(date.timeIntervalSince1970))")
            }
        case .hashtag(_, let date):
            if let date {
                tag.append("\(Int(date.timeIntervalSince1970))")
            }
        case .word(_, let date):
            if let date {
                tag.append("\(Int(date.timeIntervalSince1970))")
            }
        case .thread(_, let date):
            if let date {
                tag.append("\(Int(date.timeIntervalSince1970))")
            }
        }

        return tag
    }

    var title: String {
        switch self {
        case .user:
            return "user"
        case .hashtag:
            return "hashtag"
        case .word:
            return "word"
        case .thread:
            return "thread"
        }
    }

    init?(_ tag: [String]) {
        guard let tag_id = tag.first else { return nil }
        guard let tag_content = tag[safe: 1] else { return nil }

        let tag_expiration_date: Date? = {
            if let tag_expiration_string: String = tag[safe: 2],
               let tag_expiration_number: TimeInterval = Double(tag_expiration_string) {
                return Date(timeIntervalSince1970: tag_expiration_number)
            } else {
                return nil
            }
        }()

        switch tag_id {
        case "p":
            guard let pubkey = Pubkey(hex: tag_content) else { return nil }
            self = MuteItem.user(pubkey, tag_expiration_date)
            break
        case "t":
            self = MuteItem.hashtag(Hashtag(hashtag: tag_content), tag_expiration_date)
            break
        case "word":
            self = MuteItem.word(tag_content, tag_expiration_date)
            break
        case "thread":
            guard let note_id = NoteId(hex: tag_content) else { return nil }
            self = MuteItem.thread(note_id, tag_expiration_date)
            break
        default:
            return nil
        }
    }
}

// - MARK: TagConvertible
extension MuteItem: TagConvertible {
    enum MuteKeys: String {
        case p, t, word, e

        init?(tag: NdbTagElem) {
            let len = tag.count
            if len == 1 {
                switch tag.single_char {
                case "p": self = .p
                case "t": self = .t
                case "e": self = .e
                default: return nil
                }
            } else if len == 4 && tag.matches_str("word", tag_len: 4) {
                self = .word
            } else {
                return nil
            }
        }

        var description: String { self.rawValue }
    }

    static func from_tag(tag: TagSequence) -> MuteItem? {
        guard tag.count >= 2 else { return nil }

        var i = tag.makeIterator()

        guard let t0   = i.next(),
              let mkey = MuteKeys(tag: t0),
              let t1   = i.next()
        else {
            return nil
        }

        var expiry: Date? = nil
        if let expiry_str = i.next(), let ts = expiry_str.u64() {
            expiry = Date(timeIntervalSince1970: Double(ts))
        }

        switch mkey {
        case .p:
            return t1.id().map({ .user(Pubkey($0), expiry) })
        case .t:
            return .hashtag(Hashtag(hashtag: t1.string()), expiry)
        case .word:
            return .word(t1.string(), expiry)
        case .e:
            guard let id = t1.id() else { return nil }
            return .thread(NoteId(id), expiry)
        }
    }
}

