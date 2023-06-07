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
    
    let selected: Bool
    @State var shown: Bool
    
    init(damus_state: DamusState, event: NostrEvent, selected: Bool) {
        self.damus_state = damus_state
        self.event = event
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
                Text("Note from a user you've muted", comment: "Text to indicate that what is being shown is a note from a user who has been muted.")
                Spacer()
                Button(shown ? NSLocalizedString("Hide", comment: "Button to hide a note from a user who has been muted.") : NSLocalizedString("Show", comment: "Button to show a note from a user who has been muted.")) {
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
    
    static var previews: some View {
        
        MutedEventView(damus_state: test_damus_state(), event: test_event, selected: false)
            .frame(width: .infinity, height: 50)
    }
}
