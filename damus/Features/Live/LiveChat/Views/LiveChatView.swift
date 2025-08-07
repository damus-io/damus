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
//            HStack {
//                ProfilePicView(pubkey: event.pubkey, size: 15, highlight: .custom(DamusColors.neutral3, 1.0), profiles: state.profiles, disable_animation: state.settings.disable_animation, show_zappability: true)
//                    .onTapGesture {
//                        state.nav.push(route: Route.ProfileByKey(pubkey: event.pubkey))
//                    }
//                let profile_txn = state.profiles.lookup(id: event.pubkey)
//                let profile = profile_txn?.unsafeUnownedValue
//                let displayName = Profile.displayName(profile: profile, pubkey: event.pubkey)
//                switch displayName {
//                case .one(let one):
//                    Text(one)
//                        .font(.caption)
//                    
//                case .both(username: let username, displayName: let displayName):
//                    HStack(spacing: 6) {
//                        Text(verbatim: displayName)
//                            .font(.caption)
//                        
//                        Text(verbatim: "@\(username)")
//                            .font(.caption)
//                    }
//                }
//            }
//            .padding(.horizontal, 5)
//            
//            Text("\(event.content)")
//                .font(.caption)
        }
        .padding(.bottom, 1)
    }
}
//
//
//struct LiveChatView_Previews: PreviewProvider {
//    static var previews: some View {
//        LiveChatView(state: test_damus_state, ev: test_live_event)
//            .environmentObject(OrientationTracker())
//    }
//}
