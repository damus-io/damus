//
//  MutedEventView.swift
//  damus
//
//  Created by William Casarin on 2023-01-27.
//

import SwiftUI

struct MutedEventView: View {
    let damus_state: DamusState
    let event: NostrEvent
    let scroller: ScrollViewProxy?
    
    let selected: Bool
    @State var shown: Bool
    
    init(damus_state: DamusState, event: NostrEvent, scroller: ScrollViewProxy?, selected: Bool) {
        self.damus_state = damus_state
        self.event = event
        self.scroller = scroller
        self.selected = selected
        self._shown = State(initialValue: should_show_event(contacts: damus_state.contacts, ev: event))
    }
    
    var should_mute: Bool {
        return !should_show_event(contacts: damus_state.contacts, ev: event)
    }
    
    var MutedBox: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .foregroundColor(DamusColors.adaptableGrey)
            
            HStack {
                Text("Post from a user you've blocked", comment: "Text to indicate that what is being shown is a post from a user who has been blocked.")
                Spacer()
                Button(shown ? NSLocalizedString("Hide", comment: "Button to hide a post from a user who has been blocked.") : NSLocalizedString("Show", comment: "Button to show a post from a user who has been blocked.")) {
                    shown.toggle()
                }
            }
            .padding(10)
        }
    }
    
    var Event: some View {
        Group {
            if selected {
                SelectedEventView(damus: damus_state, event: event, size: .selected)
            } else {
                EventView(damus: damus_state, event: event)
            }
        }
    }
    
    var body: some View {
        Group {
            if should_mute {
                MutedBox
            }
            if shown {
                Event
            }
        }
        .onReceive(handle_notify(.new_mutes)) { notif in
            guard let mutes = notif.object as? [String] else {
                return
            }
            
            if mutes.contains(event.pubkey) {
                shown = false
            }
        }
        .onReceive(handle_notify(.new_unmutes)) { notif in
            guard let unmutes = notif.object as? [String] else {
                return
            }
            
            if unmutes.contains(event.pubkey) {
                shown = true
            }
        }
    }
}

struct MutedEventView_Previews: PreviewProvider {
    @State static var nav_target: NostrEvent = test_event
    @State static var navigating: Bool = false
    
    static var previews: some View {
        
        MutedEventView(damus_state: test_damus_state(), event: test_event, scroller: nil, selected: false)
            .frame(width: .infinity, height: 50)
    }
}
