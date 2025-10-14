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

    /// The expiration date for this mute item, or nil if it's a permanent mute.
    var expirationDate: Date? {
        switch self {
        case .user(_, let date), .hashtag(_, let date),
             .word(_, let date), .thread(_, let date):
            return date
        }
    }

    /// Returns true if this mute item has expired.
    func is_expired() -> Bool {
        guard let date = expirationDate else { return false }
        return date < Date()
    }

    /// Returns true if this mute is currently active (not expired).
    /// Use this to check if a mute should actually block content.
    func isActive() -> Bool {
        return !is_expired()
    }

    /// Matches for storage operations (ignores expiration, uses case-insensitive hashtag comparison).
    /// Use this for add/remove/toggle operations on the mutelist.
    func matchesStorage(_ other: MuteItem) -> Bool {
        switch (self, other) {
        case (.user(let lhs, _), .user(let rhs, _)):
            return lhs == rhs
        case (.hashtag(let lhs, _), .hashtag(let rhs, _)):
            return lhs.hashtag.caseInsensitiveCompare(rhs.hashtag) == .orderedSame
        case (.word(let lhs, _), .word(let rhs, _)):
            return lhs == rhs
        case (.thread(let lhs, _), .thread(let rhs, _)):
            return lhs == rhs
        default:
            return false
        }
    }

    /// Identity-based equality (symmetric, ignores expiration).
    /// Uses case-insensitive comparison for hashtags.
    /// Note: To check if a mute is active, use `isActive()` separately.
    static func == (lhs: MuteItem, rhs: MuteItem) -> Bool {
        return lhs.matchesStorage(rhs)
    }

    /// Hash must be consistent with equality.
    /// Uses lowercased hashtag to match case-insensitive comparison.
    func hash(into hasher: inout Hasher) {
        switch self {
        case .user(let pubkey, _):
            hasher.combine("p")
            hasher.combine(pubkey)
        case .hashtag(let hashtag, _):
            hasher.combine("t")
            hasher.combine(hashtag.hashtag.lowercased())
        case .word(let word, _):
            hasher.combine("word")
            hasher.combine(word)
        case .thread(let noteId, _):
            hasher.combine("e")
            hasher.combine(noteId)
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

