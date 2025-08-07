//
//  LiveEvent.swift
//  damus
//
//  Created by eric on 7/10/25.
//

import Foundation

enum LiveEventStatus: String {
    case planned = "SCHEDULED"
    case live = "LIVE"
    case ended = "ENDED"
}

struct LiveEvent: Hashable {
    let event: NostrEvent
    var uuid: String? = nil
    var title: String? = nil
    var summary: String? = nil
    var image: URL? = nil
    var streaming: URL? = nil
    var recording: URL? = nil
    var starts: String? = nil
    var ends: String? = nil
    var status: LiveEventStatus? = nil
    var currentParticipants: Int? = nil
    var totalParticipants: Int? = nil
    var pinned: String? = nil
    var hashtags: [String]? = nil
    var publicKeys: [Pubkey] = []
    
    static func parse(from ev: NostrEvent) -> LiveEvent {
        var liveEvent = LiveEvent(event: ev)
        
        for tag in ev.tags {
            guard tag.count >= 2 else { continue }
            switch tag[0].string() {
            case "title":   liveEvent.title = tag[1].string()
            case "d": liveEvent.uuid = tag[1].string()
            case "image":   liveEvent.image = URL(string: tag[1].string())
            case "summary": liveEvent.summary = tag[1].string()
            case "streaming": liveEvent.streaming = URL(string: tag[1].string())
            case "recording": liveEvent.recording = URL(string: tag[1].string())
            case "starts": liveEvent.starts = tag[1].string()
            case "ends": liveEvent.ends = tag[1].string()
            case "status":
                if tag[1].string() == "planned" {
                    liveEvent.status = .planned
                } else if tag[1].string() == "live" {
                    liveEvent.status = .live
                } else if tag[1].string() == "ended" {
                    liveEvent.status = .ended
                }
            case "current_participants": liveEvent.currentParticipants = Int(tag[1].string())
            case "total_participants": liveEvent.totalParticipants = Int(tag[1].string())
            case "pinned": liveEvent.pinned = tag[1].string()
            case "t":
                if (liveEvent.hashtags?.append(tag[1].string())) == nil {
                    liveEvent.hashtags = [tag[1].string()]
                }
            case "p":
                liveEvent.publicKeys.append(Pubkey(Data(hex: tag[1].string())))
            default:
                break
            }
        }
        
        return liveEvent
    }
}
