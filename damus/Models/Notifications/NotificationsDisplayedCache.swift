//
//  NotificationsDisplayedCache.swift
//  damus
//
//  Created by Daniel D’Aquino on 2023-11-22.
//

import Foundation

struct NotificationsDisplayedCache {
    // Constants
    private let default_suite_name: String = "group.com.damus"  // Shared defaults for this app group
    private let cache_defaults_key: String = "notifications_displayed_cache"
    private let cache_next_purge_date_key: String = "notifications_displayed_cache_next_purge_date"
    private let cache_default_time_to_live: TimeInterval = 60 * 60 * 24     // 1 day
    
    // Convenience objects
    static var shared: Self = NotificationsDisplayedCache()
    
    // Internal properties
    private let defaults: UserDefaults?
    private var time_to_live: TimeInterval
    
    private var cache: [String: Date] { // NoteIds have to be String-encoded to be accepted by the system when saving
        get {
            return defaults?.object(forKey: cache_defaults_key) as? [String: Date] ?? [:]
        }
        set {
            defaults?.setValue(newValue, forKey: cache_defaults_key)
        }
    }
    
    private var next_purge: Date {
        get {
            return defaults?.object(forKey: cache_next_purge_date_key) as? Date ?? Date().addingTimeInterval(-1)
        }
        set {
            defaults?.setValue(newValue, forKey: cache_next_purge_date_key)
        }
    }
    
    init(suite_name: String? = nil, time_to_live: TimeInterval? = nil) {
        self.defaults = UserDefaults(suiteName: suite_name ?? default_suite_name)
        self.time_to_live = time_to_live ?? cache_default_time_to_live
    }
    
    init(defaults: UserDefaults, time_to_live: TimeInterval? = nil) {
        self.defaults = defaults
        self.time_to_live = time_to_live ?? cache_default_time_to_live
    }
    
    func has_displayed(note_id: NoteId) -> Bool {
        return cache[note_id.hex()] != nil
    }
    
    mutating func set_has_displayed(note_id: NoteId) {
        cache[note_id.hex()] = Date()
    }
    
    mutating func purge_old_entries(force: Bool = false) {
        if !force && Date.now < next_purge {
            return  // Not time to purge yet
        }
        for (note_id, displayed_date) in cache {
            if Date.now.timeIntervalSince(displayed_date) > time_to_live {
                cache[note_id] = nil
            }
        }
    }
    
    mutating func clear_all() {
        cache = [:]
    }
    
    /// Convenience function that handles everything you likely need.
    /// It automatically purges old entries, checks if the note was already displayed for you, and registers that the note was displayed.
    /// Note: This function assumes that if you receive `false`, you will display the notification. If not, please use functions individually
    /// - Parameter note_id: The note\_id you would like to display on a notification
    /// - Returns: `false` if there is no register of it being shown, `true` otherwise. If `false`, the cache will assume you showed the notification
    mutating func check_and_register(note_id: NoteId) -> Bool {
        self.purge_old_entries()
        let has_displayed = self.has_displayed(note_id: note_id)
        if !has_displayed {
            self.set_has_displayed(note_id: note_id)
        }
        return has_displayed
    }
}
