//
//  BookmarksManager.swift
//  damus
//
//  Created by Joel Klabo on 2/18/23.
//

import Foundation

class BookmarksManager {
    static private let userDefaults = UserDefaults.standard
    
    static var bookmarks: [String] {
        get {
            return userDefaults.stringArray(forKey: "bookmarks") ?? []
        }
        set {
            let uniqueBookmarks = Array(Set(newValue))
            if uniqueBookmarks != bookmarks {
                userDefaults.set(uniqueBookmarks, forKey: "bookmarks")
            }
        }
    }
    
    static func isBookmarked(_ string: String) -> Bool {
        return bookmarks.contains(string)
    }
    
    static func updateBookmark(_ string: String) {
        if isBookmarked(string) {
            bookmarks = bookmarks.filter { $0 != string }
        } else {
            bookmarks.append(string)
        }
    }
    
    static func clearAll() {
        bookmarks = []
    }
}
