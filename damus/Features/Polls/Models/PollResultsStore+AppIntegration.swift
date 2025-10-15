//
//  PollResultsStore+AppIntegration.swift
//  damus
//
//  Created by ChatGPT on 2025-04-11.
//

import Foundation

extension NostrNetworkManager: PollResponseNetworking {
    func subscribeToPollResponses(poll: PollEvent, subId: String, handler: @escaping (NostrResponse) -> Void) {
        let filter = NostrFilter(kinds: [.poll_response], referenced_ids: [poll.id])
        let relays = poll.relayHints.isEmpty ? nil : poll.relayHints

        pool.subscribe_to(sub_id: subId, filters: [filter], to: relays) { _, event in
            guard case .nostr_event(let response) = event else { return }
            handler(response)
        }
    }

    func sendPollResponseEvent(_ event: NostrEvent, relayHints: [RelayURL]?) {
        postbox.send(event, to: relayHints)
    }
}

extension DamusState: PollVotingContext {
    var pollNetwork: PollResponseNetworking { nostrNetwork }
}
