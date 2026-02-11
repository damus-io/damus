//
//  EventMutingContainerView.swift
//  damus
//
//  Created by William Casarin on 2023-01-27.
//

import SwiftUI

/// A container view that shows or hides provided content based on whether the given event should be muted or not, with built-in user controls to show or hide content, and an option to customize the muted box
struct EventMutingContainerView<Content: View, MuteBox: View>: View {

    let damus_state: DamusState
    let event: NostrEvent
    let content: Content
    let customMuteBox: ((Binding<Bool>, MuteItem?) -> MuteBox)?

    /// Represents if the note itself should be shown.
    ///
    /// By default this is the same as `should_show_event`. However, if the user taps the button to manually show a muted note, this can become out of sync with `should_show_event`.
    @State var shown: Bool

    @State var muted_reason: MuteItem?

    init(damus_state: DamusState, event: NostrEvent, @ViewBuilder content: () -> Content) where MuteBox == EmptyView {
        self.damus_state = damus_state
        self.event = event
        self.content = content()
        self.customMuteBox = nil
        self._shown = State(initialValue: should_show_event(state: damus_state, ev: event))
    }

    init(damus_state: DamusState, event: NostrEvent, muteBox: @escaping (Binding<Bool>, MuteItem?) -> MuteBox, @ViewBuilder content: () -> Content) {
        self.damus_state = damus_state
        self.event = event
        self.content = content()
        self.customMuteBox = muteBox
        self._shown = State(initialValue: should_show_event(state: damus_state, ev: event))
    }

    var should_mute: Bool {
        return !should_show_event(state: damus_state, ev: event)
    }

    var body: some View {
        innerBody
            .onReceive(handle_notify(.new_mutes)) { mutes in
                let new_muted_event_reason = damus_state.mutelist_manager.event_muted_reason(event)
                if new_muted_event_reason != nil {
                    shown = false
                    muted_reason = new_muted_event_reason
                }
            }
            .onReceive(handle_notify(.new_unmutes)) { unmutes in
                if damus_state.mutelist_manager.event_muted_reason(event) != nil {
                    shown = true
                    muted_reason = nil
                }
            }
    }

    @ViewBuilder
    private var innerBody: some View {
        if should_mute {
            if let customMuteBox {
                customMuteBox($shown, muted_reason)
            }
            else {
                EventMutedBoxView(shown: $shown, reason: muted_reason)
            }
        }
        if shown {
            self.content
        }
    }
}

/// A box that instructs the user about a content that has been muted.
struct EventMutedBoxView: View {
    @Binding var shown: Bool
    var reason: MuteItem?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .foregroundColor(DamusColors.adaptableGrey)
            
            HStack {
                if let reason {
                    Text("Note from a \(reason.title) you've muted", comment: "Text to indicate that what is being shown is a note which has been muted.")
                } else {
                    Text("Note you've muted", comment: "Text to indicate that what is being shown is a note which has been muted.")
                }
                Spacer()
                Button(shown ? NSLocalizedString("Hide", comment: "Button to hide a note which has been muted.") : NSLocalizedString("Show", comment: "Button to show a note which has been muted.")) {
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
