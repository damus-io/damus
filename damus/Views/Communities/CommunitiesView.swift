//
//  CommunitiesView.swift
//  damus
//
//  Created by Daniel D’Aquino on 2025-05-09.
//

import SwiftUI

struct CommunitiesView: View {
    var damus: DamusState
    @StateObject var model: CommunityModel
    
    init(damus: DamusState, communityId: NIP73.ID.Value) {
        self.damus = damus
        let loading = State(initialValue: true)
        self._model = StateObject(wrappedValue: CommunityModel(id: communityId, damus: damus))
    }
    
    var body: some View {
        ZStack {
            self.timeline
            
            if damus.keypair.privkey != nil {
                PostButtonContainer(is_left_handed: damus.settings.left_handed) {
                    present_sheet(.post(.posting_to(community: model.id)))
                }
                .padding(.bottom, tabHeight + getSafeAreaBottom())
//                .opacity(0.35 + abs(1.25 - (abs(headerOffset/100.0))))
            }
        }
        .onAppear {
            model.load()
        }
        .refreshable {
            model.load()
        }
    }
    
    var timeline: some View {
        TimelineView(
            events: model.events,
            loading: .constant(model.loading),
            damus: damus,
            show_friend_icon: false,
            filter: ContentFilters.default_filters(damus_state: damus).filter,
            apply_mute_rules: true,
            content: {
                VStack {
                    switch model.id {
                    case .hashtag(let tag): Text("#\(tag)")
                    case .url(url: let url):
                        Text("URL community: \(url.absoluteString)")
                    case .geo(let geohash):
                        Text("GEO community: \(geohash)")
                    case .unsupported(kind: let kind, value: let value):
                        Text("Unsupported.")
                    }
                }
                .font(.title)
            }
        )
    }
}

#Preview {
    CommunitiesView(
        damus: test_damus_state,
        communityId: .hashtag("test")
    )
}
