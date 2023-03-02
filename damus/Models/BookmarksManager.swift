//
//  BookmarksManager.swift
//  damus
//
//  Created by Joel Klabo on 2/18/23.
//

import Foundation

class BookmarksManager {
    
    private let userDefaults = UserDefaults.standard
    private let pubkey: String
    
    init(pubkey: String) {
        self.pubkey = pubkey
    }
    
    var bookmarks: [String] {
        get {
            return userDefaults.stringArray(forKey: storageKey()) ?? []
        }
        set {
            let uniqueBookmarks = Array(Set(newValue))
            if uniqueBookmarks != bookmarks {
                userDefaults.set(uniqueBookmarks, forKey: storageKey())
            }
        }
    }
    
    func isBookmarked(_ string: String) -> Bool {
        return bookmarks.contains(string)
    }
    
    func updateBookmark(_ string: String) {
        if isBookmarked(string) {
            bookmarks = bookmarks.filter { $0 != string }
        } else {
            bookmarks.append(string)
        }
    }
    
    func clearAll() {
        bookmarks = []
    }
    
    private func storageKey() -> String {
        pk_setting_key(pubkey, key: "bookmarks")
    }
}
