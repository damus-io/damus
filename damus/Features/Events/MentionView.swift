//
//  MentionView.swift
//  damus
//
//  Created by Daniel D’Aquino on 2023-09-27.
//

import SwiftUI

struct MentionView: View {
    let damus_state: DamusState
    let mention: Mention<NoteId>
    
    init(damus_state: DamusState, mention: Mention<NoteId>) {
        self.damus_state = damus_state
        self.mention = mention
    }
    
    var body: some View {
        EventLoaderView(damus_state: damus_state, event_id: mention.ref) { event in
            EventMutingContainerView(damus_state: damus_state, event: event) {
                BuilderEventView(damus: damus_state, event_id: mention.ref)
            }
        }
    }
}

struct MentionView_Previews: PreviewProvider {
    static var previews: some View {
        MentionView(damus_state: test_damus_state, mention: .note(test_note.id))
    }
}
