//
//  LiveChatView.swift
//  damus
//
//  Created by eric on 8/7/25.
//

import SwiftUI
import Kingfisher

struct LiveChatView: View {
    let state: DamusState
    let event: NostrEvent

    @Environment(\.colorScheme) var colorScheme

    @ObservedObject var artifacts: NoteArtifactsModel

    init(state: DamusState, ev: NostrEvent) {
        self.state = state
        self.event = ev

        self._artifacts = ObservedObject(wrappedValue: state.events.get_cache_data(ev.id).artifacts_model)
    }

    func content_filter(_ pubkeys: [Pubkey]) -> ((NostrEvent) -> Bool) {
        var filters = ContentFilters.defaults(damus_state: self.state)
        filters.append({ pubkeys.contains($0.pubkey) })
        return ContentFilters(filters: filters).filter
    }

    var body: some View {
        VStack(alignment: .leading) {
            TextEvent(damus: state, event: event, pubkey: event.pubkey, options: [.no_action_bar,.small_pfp,.wide,.no_previews,.small_text])
        }
        .padding(.bottom, 1)
    }
}
