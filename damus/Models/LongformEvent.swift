//
//  LongformEvent.swift
//  damus
//
//  Created by Daniel Nogueira on 2023-11-24.
//

import Foundation

struct LongformEvent {
    let event: NostrEvent
    
    var title: String? = nil
    var image: URL? = nil
    var summary: String? = nil
    var published_at: Date? = nil
    
    static func parse(from ev: NostrEvent) -> LongformEvent {
        var longform = LongformEvent(event: ev)
        
        for tag in ev.tags {
            guard tag.count >= 2 else { continue }
            switch tag[0].string() {
            case "title":   longform.title = tag[1].string()
            case "image":   longform.image = URL(string: tag[1].string())
            case "summary": longform.summary = tag[1].string()
            case "published_at":
                longform.published_at = Double(tag[1].string()).map { d in Date(timeIntervalSince1970: d) }
            default:
                break
            }
        }
        
        return longform
    }
}
