//
//  EventMutingContainerView.swift
//  damus
//
//  Created by William Casarin on 2023-01-27.
//

import SwiftUI

/// A container view that shows or hides provided content based on whether the given event should be muted or not, with built-in user controls to show or hide content, and an option to customize the muted box
struct EventMutingContainerView<Content: View>: View {
    typealias MuteBoxViewClosure = ((_ shown: Binding<Bool>) -> AnyView)
    
    let damus_state: DamusState
    let event: NostrEvent
    let content: Content
    var customMuteBox: MuteBoxViewClosure?
    
    @State var shown: Bool
    
    init(damus_state: DamusState, event: NostrEvent, @ViewBuilder content: () -> Content) {
        self.damus_state = damus_state
        self.event = event
        self.content = content()
        self._shown = State(initialValue: should_show_event(keypair: damus_state.keypair, hellthreads: damus_state.muted_threads, contacts: damus_state.contacts, ev: event))
    }
    
    init(damus_state: DamusState, event: NostrEvent, muteBox: @escaping MuteBoxViewClosure, @ViewBuilder content: () -> Content) {
        self.init(damus_state: damus_state, event: event, content: content)
        self.customMuteBox = muteBox
    }
    
    var should_mute: Bool {
        return !should_show_event(keypair: damus_state.keypair, hellthreads: damus_state.muted_threads, contacts: damus_state.contacts, ev: event)
    }
    
    var body: some View {
        Group {
            if should_mute {
                if let customMuteBox {
                    customMuteBox($shown)
                }
                else {
                    EventMutedBoxView(shown: $shown)
                }
            }
            if shown {
                self.content
            }
        }
        .onReceive(handle_notify(.new_mutes)) { mutes in
            if mutes.contains(event.pubkey) {
                shown = false
            }
        }
        .onReceive(handle_notify(.new_unmutes)) { unmutes in
            if unmutes.contains(event.pubkey) {
                shown = true
            }
        }
    }
}

/// A box that instructs the user about a content that has been muted.
struct EventMutedBoxView: View {
    @Binding var shown: Bool
    
    var body: some View {
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
}

struct MutedEventView_Previews: PreviewProvider {
    
    static var previews: some View {
        
        EventMutingContainerView(damus_state: test_damus_state, event: test_note) {
            EventView(damus: test_damus_state, event: test_note)
        }
            .frame(width: .infinity, height: 50)
    }
}
