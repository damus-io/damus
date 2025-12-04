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
    @State private var friend_filter: FriendFilter

    init(damus_state: DamusState, model: NIP05DomainEventsModel, nip05_domain_favicon: FaviconURL?) {
        self.damus_state = damus_state
        self.model = model
        self.nip05_domain_favicon = nip05_domain_favicon
        self._friend_filter = State(initialValue: model.friend_filter)
    }

    private func nip05MatchesDomain(_ pubkey: Pubkey) -> Bool {
        if let validated = damus_state.profiles.is_validated(pubkey),
           validated.host.caseInsensitiveCompare(model.domain) == .orderedSame {
            return true
        }

        let profile = damus_state.profiles.lookup(id: pubkey)?.unsafeUnownedValue
        guard let nip05_str = profile?.nip05,
              let nip05 = NIP05.parse(nip05_str) else {
            return false
        }

        return nip05.host.caseInsensitiveCompare(model.domain) == .orderedSame
    }

    func nip05_filter(ev: NostrEvent) -> Bool {
        guard friend_filter.filter(contacts: damus_state.contacts, pubkey: ev.pubkey) else {
            return false
        }

        return nip05MatchesDomain(ev.pubkey)
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
                NIP05DomainTimelineHeaderView(damus_state: damus_state, model: model, nip05_domain_favicon: nip05_domain_favicon, friend_filter: friend_filter)
                    .padding(.leading, 30)
                    .padding(.top, 30)
            }
        }
        .ignoresSafeArea()
        .padding(.bottom, tabHeight)
        .onAppear {
            guard model.events.all_events.isEmpty else { return }

            model.subscribe()
        }
        .onDisappear {
            model.unsubscribe()
        }
        .safeAreaInset(edge: .bottom) {
            if model.has_more {
                Button {
                    model.load_more()
                } label: {
                    if model.loading_more {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .padding(.vertical, 8)
                    } else {
                        Text("Load older notes")
                            .font(.subheadline.weight(.semibold))
                            .padding(.vertical, 8)
                    }
                }
                .frame(maxWidth: .infinity)
                .background(.ultraThinMaterial)
            } else {
                EmptyView()
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                TrustedNetworkButton(filter: $friend_filter)
            }
        }
        .onChange(of: friend_filter) { val in
            damus_state.settings.friend_filter = val
            Task { @MainActor in
                model.set_friend_filter(val)
            }
        }
        .onAppear {
            if friend_filter != damus_state.settings.friend_filter {
                friend_filter = damus_state.settings.friend_filter
            }
        }
    }
}

#Preview {
    let damus_state = test_damus_state
    let model = NIP05DomainEventsModel(state: damus_state, domain: "damus.io")
    let nip05_domain_favicon = FaviconURL(source: URL(string: "https://damus.io/favicon.ico")!, format: .ico, sourceType: .ico)
    NIP05DomainTimelineView(damus_state: test_damus_state, model: model, nip05_domain_favicon: nip05_domain_favicon)
}
