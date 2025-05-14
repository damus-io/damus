//
//  FollowPackEvent.swift
//  damus
//
//  Created by eric on 4/30/25.
//


import Foundation

struct FollowPackEvent {
    let event: NostrEvent
    var title: String? = nil
    var uuid: String? = nil
    var image: URL? = nil
    var description: String? = nil
    var publicKeys: [Pubkey] = []
    
    
    static func parse(from ev: NostrEvent) -> FollowPackEvent {
        var followlist = FollowPackEvent(event: ev)
        
        for tag in ev.tags {
            guard tag.count >= 2 else { continue }
            switch tag[0].string() {
            case "title":   followlist.title = tag[1].string()
            case "d": followlist.uuid = tag[1].string()
            case "image":   followlist.image = URL(string: tag[1].string())
            case "description": followlist.description = tag[1].string()
            case "p":
                followlist.publicKeys.append(Pubkey(Data(hex: tag[1].string())))
            default:
                break
            }
        }
        
        return followlist
    }
}
