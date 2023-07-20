//
//  SuggestedUsersViewModel.swift
//  damus
//
//  Created by klabo on 7/17/23.
//

import Foundation
import Combine

struct SuggestedUserGroup: Identifiable, Codable {
    let id = UUID()
    let title: String
    let users: [String]

    enum CodingKeys: String, CodingKey {
        case title, users
    }
}


class SuggestedUsersViewModel: ObservableObject {

    public let damus_state: DamusState

    @Published var groups: [SuggestedUserGroup] = []

    private let sub_id = UUID().uuidString

    init(damus_state: DamusState) {
        self.damus_state = damus_state
        loadSuggestedUserGroups()
        let pubkeys = getPubkeys(groups: groups)
        subscribeToSuggestedProfiles(pubkeys: pubkeys)
    }

    func suggestedUser(pubkey: String) -> SuggestedUser? {
        if let profile = damus_state.profiles.lookup(id: pubkey),
           let user = SuggestedUser(profile: profile, pubkey: pubkey) {
            return user
        }
        return nil
    }

    func follow(pubkeys: [String]) {
        for pubkey in pubkeys {
            notify(.follow, FollowTarget.pubkey(pubkey))
        }
    }

    private func loadSuggestedUserGroups() {
        guard let url = Bundle.main.url(forResource: "suggested_users", withExtension: "json") else {
            return
        }

        guard let data = try? Data(contentsOf: url) else {
            return
        }

        let decoder = JSONDecoder()
        do {
            let groups = try decoder.decode([SuggestedUserGroup].self, from: data)
            self.groups = groups
        } catch {
            print(error.localizedDescription.localizedLowercase)
        }
    }

    private func getPubkeys(groups: [SuggestedUserGroup]) -> [String] {
        var pubkeys: [String] = []
        for group in groups {
            pubkeys.append(contentsOf: group.users)
        }
        return pubkeys
    }

    private func subscribeToSuggestedProfiles(pubkeys: [String]) {
        let filter = NostrFilter(kinds: [.metadata],
                                 authors: pubkeys)
        damus_state.pool.subscribe(sub_id: sub_id, filters: [filter], handler: handle_event)
    }

    func handle_event(relay_id: String, ev: NostrConnectionEvent) {
        guard case .nostr_event(let nev) = ev else {
            return
        }

        switch nev {
        case .event(let sub_id, let ev):
            guard sub_id == self.sub_id else {
                return
            }

            if ev.known_kind == .metadata {
                process_metadata_event(events: damus_state.events, our_pubkey: damus_state.pubkey, profiles: damus_state.profiles, ev: ev)
            }

        case .notice(let msg):
            print("suggested user profiles notice: \(msg)")

        case .eose:
            self.objectWillChange.send()

        case .ok:
            break
        }
    }
}
