//
//  NIP05DomainTimelineView.swift
//  damus
//
//  Created by Terry Yiu on 4/11/25.
//

import FaviconFinder
import Kingfisher
import SwiftUI

struct NIP05DomainTimelineView: View {
    let damus_state: DamusState
    @ObservedObject var model: NIP05DomainEventsModel
    let nip05_domain_favicon: FaviconURL?

    func nip05_filter(ev: NostrEvent) -> Bool {
        damus_state.contacts.is_in_friendosphere(ev.pubkey) && damus_state.profiles.is_validated(ev.pubkey) != nil
    }

    var contentFilters: ContentFilters {
        var filters = Array<(NostrEvent) -> Bool>()
        filters.append(contentsOf: ContentFilters.defaults(damus_state: damus_state))
        filters.append(nip05_filter)
        return ContentFilters(filters: filters)
    }

    var body: some View {
        let height: CGFloat = 250.0

        TimelineView(events: model.events, loading: $model.loading, damus: damus_state, show_friend_icon: true, filter: contentFilters.filter(ev:)) {
            ZStack(alignment: .leading) {
                DamusBackground(maxHeight: height)
                    .mask(LinearGradient(gradient: Gradient(colors: [.black, .black, .black, .clear]), startPoint: .top, endPoint: .bottom))
                NIP05DomainTimelineHeaderView(damus_state: damus_state, model: model, nip05_domain_favicon: nip05_domain_favicon)
                    .padding(.leading, 30)
                    .padding(.top, 30)
            }
        }
        .ignoresSafeArea()
        .padding(.bottom, tabHeight)
        .onAppear {
            guard model.events.all_events.isEmpty else { return }

            model.subscribe()

            if let pubkeys = model.filter.authors {
                for pubkey in pubkeys {
                    check_nip05_validity(pubkey: pubkey, damus_state: damus_state)
                }
            }
        }
        .onDisappear {
            model.unsubscribe()
        }
    }
}

#Preview {
    let damus_state = test_damus_state
    let model = NIP05DomainEventsModel(state: damus_state, domain: "damus.io")
    let nip05_domain_favicon = FaviconURL(source: URL(string: "https://damus.io/favicon.ico")!, format: .ico, sourceType: .ico)
    NIP05DomainTimelineView(damus_state: test_damus_state, model: model, nip05_domain_favicon: nip05_domain_favicon)
}
