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
    @Binding var nav_target: String?
    @Binding var navigating: Bool
    @State var shown: Bool
    @Environment(\.colorScheme) var colorScheme
    
    init(damus_state: DamusState, event: NostrEvent, scroller: ScrollViewProxy?, nav_target: Binding<String?>, navigating: Binding<Bool>, selected: Bool) {
        self.damus_state = damus_state
        self.event = event
        self.scroller = scroller
        self.selected = selected
        self._nav_target = nav_target
        self._navigating = navigating
        self._shown = State(initialValue: should_show_event(contacts: damus_state.contacts, ev: event))
    }
    
    var should_mute: Bool {
        return !should_show_event(contacts: damus_state.contacts, ev: event)
    }
    
    var FillColor: Color {
        colorScheme == .light ? Color("DamusLightGrey") : Color("DamusDarkGrey")
    }
    
    var MutedBox: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .foregroundColor(FillColor)
            
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
                SelectedEventView(damus: damus_state, event: event)
            } else {
                EventView(damus: damus_state, event: event, has_action_bar: true)
                    .onTapGesture {
                        nav_target = event.id
                        navigating = true
                    }
                    .onAppear {
                        // TODO: find another solution to prevent layout shifting and layout blocking on large responses
                        scroller?.scrollTo("main", anchor: .bottom)
                    }
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
    @State static var nav_target: String? = nil
    @State static var navigating: Bool = false
    
    static var previews: some View {
        
        MutedEventView(damus_state: test_damus_state(), event: test_event, scroller: nil, nav_target: $nav_target, navigating: $navigating, selected: false)
            .frame(width: .infinity, height: 50)
    }
}
