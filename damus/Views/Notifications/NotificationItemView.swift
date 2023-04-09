//
//  NotificationItemView.swift
//  damus
//
//  Created by William Casarin on 2023-02-21.
//

import SwiftUI

enum ShowItem {
    case show(NostrEvent?)
    case dontshow(NostrEvent?)
}

func notification_item_event(events: EventCache, notif: NotificationItem) -> ShowItem {
    switch notif {
    case .repost(let evid, _):
        return .dontshow(events.lookup(evid))
    case .reply(let ev):
        return .show(ev)
    case .reaction(let evid, _):
        return .dontshow(events.lookup(evid))
    case .event_zap(let evid, _):
        return .dontshow(events.lookup(evid))
    case .profile_zap:
        return .show(nil)
    }
}

struct NotificationItemView: View {
    let state: DamusState
    let item: NotificationItem
    
    var show_item: ShowItem {
        notification_item_event(events: state.events, notif: item)
    }
    
    var options: EventViewOptions {
        if state.settings.truncate_mention_text {
            return [.wide, .truncate_content]
        }
        
        return [.wide]
    }
    
    func Item(_ ev: NostrEvent?) -> some View {
        Group {
            switch item {
            case .repost(_, let evgrp):
                EventGroupView(state: state, event: ev, group: .repost(evgrp))
                
            case .event_zap(_, let zapgrp):
                EventGroupView(state: state, event: ev, group: .zap(zapgrp))
                
            case .profile_zap(let grp):
                EventGroupView(state: state, event: nil, group: .profile_zap(grp))
            
            case .reaction(_, let evgrp):
                EventGroupView(state: state, event: ev, group: .reaction(evgrp))
            
            case .reply(let ev):
                NavigationLink(destination: ThreadView(state: state, thread: ThreadModel(event: ev, damus_state: state))) {
                    EventView(damus: state, event: ev, options: options)
                }
                .buttonStyle(.plain)
            }
            
            ThiccDivider()
        }
    }
    
    var body: some View {
        Group {
            switch show_item {
            case .show(let ev):
                Item(ev)
                
            case .dontshow(let ev):
                if let ev {
                    Item(ev)
                }
            }
        }
    }
}

let test_notification_item: NotificationItem = .repost("evid", test_event_group)

struct NotificationItemView_Previews: PreviewProvider {
    static var previews: some View {
        NotificationItemView(state: test_damus_state(), item: test_notification_item)
    }
}
