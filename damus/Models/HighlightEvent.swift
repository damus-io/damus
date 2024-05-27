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

    static func parse(from ev: NostrEvent) -> HighlightEvent {
        var highlight = HighlightEvent(event: ev)

        for tag in ev.tags {
            guard tag.count >= 2 else { continue }
            switch tag[0].string() {
            case "e":   highlight.event_ref = tag[1].string()
            case "a":   highlight.event_ref = tag[1].string()
            case "r":   highlight.url_ref = URL(string: tag[1].string())
            case "context": highlight.context = tag[1].string()
            default:
                break
            }
        }

        return highlight
    }
}
