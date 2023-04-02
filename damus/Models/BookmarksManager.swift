//
//  BookmarksManager.swift
//  damus
//
//  Created by Joel Klabo on 2/18/23.
//

import Foundation

fileprivate func get_bookmarks_key(pubkey: String) -> String {
    pk_setting_key(pubkey, key: "bookmarks")
}

func load_bookmarks(pubkey: String) -> [NostrEvent] {
    let key = get_bookmarks_key(pubkey: pubkey)
    return (UserDefaults.standard.stringArray(forKey: key) ?? []).compactMap {
        event_from_json(dat: $0)
    }
}

func save_bookmarks(pubkey: String, current_value: [NostrEvent], value: [NostrEvent]) -> Bool {
    let uniq_bookmarks = Array(Set(value))
    
    if uniq_bookmarks != current_value {
        let encoded = uniq_bookmarks.map(event_to_json)
        UserDefaults.standard.set(encoded, forKey: get_bookmarks_key(pubkey: pubkey))
        return true
    }
    
    return false
}

class BookmarksManager: ObservableObject {
    
    private let userDefaults = UserDefaults.standard
    private let pubkey: String
    
    private var _bookmarks: [NostrEvent]
    var bookmarks: [NostrEvent] {
        get {
            return _bookmarks
        }
        set {
            if save_bookmarks(pubkey: pubkey, current_value: _bookmarks, value: newValue) {
                self._bookmarks = newValue
                self.objectWillChange.send()
            }
        }
    }
    
    init(pubkey: String) {
        self._bookmarks = load_bookmarks(pubkey: pubkey)
        self.pubkey = pubkey
    }
    
    func isBookmarked(_ ev: NostrEvent) -> Bool {
        return bookmarks.contains(ev)
    }
    
    func updateBookmark(_ ev: NostrEvent) {
        if isBookmarked(ev) {
            bookmarks = bookmarks.filter { $0 != ev }
        } else {
            bookmarks.insert(ev, at: 0)
        }
    }
    
    func clearAll() {
        bookmarks = []
    }
}
