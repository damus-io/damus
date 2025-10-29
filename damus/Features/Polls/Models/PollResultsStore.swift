//
//  PollResultsStore.swift
//  damus
//
//  Created by ChatGPT on 2025-04-02.
//

import Foundation

@MainActor
final class PollResultsStore: ObservableObject {
    enum PollVoteError: Error {
        case noKeypair
        case noSelection
        case pollClosed
        case invalidSelection
        case eventBuildFailed
    }

    struct PollState {
        var poll: PollEvent
        var ballotsByPubkey: [Pubkey: Ballot]

        init(poll: PollEvent, ballotsByPubkey: [Pubkey: Ballot] = [:]) {
            self.poll = poll
            self.ballotsByPubkey = ballotsByPubkey
        }

        var id: NoteId { poll.id }

        var tallies: [String: Int] {
            var counts: [String: Int] = Dictionary(uniqueKeysWithValues: poll.options.map { ($0.id, 0) })
            for ballot in ballotsByPubkey.values {
                for selection in ballot.selections {
                    counts[selection, default: 0] += 1
                }
            }
            return counts
        }

        var totalVotes: Int {
            ballotsByPubkey.values.reduce(0) { acc, ballot in
                acc + ballot.selections.count
            }
        }

        var voterCount: Int {
            ballotsByPubkey.keys.count
        }

        func hasVoted(pubkey: Pubkey) -> Bool {
            ballotsByPubkey[pubkey] != nil
        }

        func selections(for pubkey: Pubkey) -> [String]? {
            ballotsByPubkey[pubkey]?.selections
        }
    }

    struct Ballot {
        let eventId: NoteId
        let createdAt: UInt32
        let selections: [String]
    }

    @Published private(set) var polls: [NoteId: PollState] = [:]

    private var pendingResponses: [NoteId: [PollResponse]] = [:]
    private var subscriptions: [NoteId: String] = [:]

    func reset() {
        polls.removeAll()
        pendingResponses.removeAll()
        subscriptions.removeAll()
    }

    func registerPollEvent(_ event: NostrEvent) {
        guard let pollEvent = PollEvent(event: event) else { return }

        var state = polls[pollEvent.id] ?? PollState(poll: pollEvent)
        state.poll = pollEvent

        if var queuedResponses = pendingResponses[pollEvent.id] {
            var didChange = false
            for response in queuedResponses {
                if apply(response: response, to: &state) {
                    didChange = true
                }
            }
            if didChange {
                polls[pollEvent.id] = state
            } else {
                polls[pollEvent.id] = state
            }
            queuedResponses.removeAll()
            pendingResponses[pollEvent.id] = nil
        } else {
            polls[pollEvent.id] = state
        }
    }

    func registerResponseEvent(_ event: NostrEvent) {
        guard let response = PollResponse(event: event) else { return }

        if var state = polls[response.pollId] {
            guard apply(response: response, to: &state) else { return }
            polls[response.pollId] = state
        } else {
            pendingResponses[response.pollId, default: []].append(response)
        }
    }

    func ensureResults(for poll: PollEvent, network: NostrNetworkManager) {
        if subscriptions[poll.id] != nil { return }
        let subid = "poll-\(poll.id.hex())"
        subscriptions[poll.id] = subid

        let filter = NostrFilter(kinds: [.poll_response], referenced_ids: [poll.id])
        let relays = poll.relayHints.isEmpty ? nil : poll.relayHints

        network.pool.subscribe_to(sub_id: subid, filters: [filter], to: relays) { [weak self] _, event in
            guard let self else { return }
            guard case .nostr_event(let response) = event else { return }

            switch response {
            case .event(_, let nostrEvent):
                Task { @MainActor in
                    self.registerResponseEvent(nostrEvent)
                }
            case .eose:
                break
            default:
                break
            }
        }
    }

    func submitVote(for poll: PollEvent, selections: [String], damusState: DamusState) -> Result<Void, PollVoteError> {
        guard let keypair = damusState.keypair.to_full() else { return .failure(.noKeypair) }
        guard !selections.isEmpty else { return .failure(.noSelection) }
        guard !poll.isExpired(now: Date()) else { return .failure(.pollClosed) }

        let sanitized = sanitizedSelectionIDs(from: selections, poll: poll)
        guard !sanitized.isEmpty else { return .failure(.invalidSelection) }

        guard let event = PollVoteBuilder.makeResponseEvent(poll: poll, selections: sanitized, keypair: keypair) else {
            return .failure(.eventBuildFailed)
        }

        damusState.nostrNetwork.postbox.send(event, to: poll.relayHints.isEmpty ? nil : poll.relayHints)
        registerResponseEvent(event)
        return .success(())
    }

    func state(for pollId: NoteId) -> PollState? {
        polls[pollId]
    }

    func tallies(for pollId: NoteId) -> [String: Int]? {
        polls[pollId]?.tallies
    }

    func hasVoted(pollId: NoteId, pubkey: Pubkey) -> Bool {
        polls[pollId]?.hasVoted(pubkey: pubkey) ?? false
    }

    func selections(for pollId: NoteId, pubkey: Pubkey) -> [String]? {
        polls[pollId]?.selections(for: pubkey)
    }

    private func apply(response: PollResponse, to state: inout PollState) -> Bool {
        if state.poll.isExpired(at: response.createdAt) {
            return false
        }

        let sanitizedSelections = sanitizeSelections(from: response, poll: state.poll)
        guard !sanitizedSelections.isEmpty else { return false }

        let incomingBallot = Ballot(eventId: response.responseId, createdAt: response.createdAt, selections: sanitizedSelections)

        if let existing = state.ballotsByPubkey[response.responder] {
            if existing.createdAt > incomingBallot.createdAt {
                return false
            }

            if existing.createdAt == incomingBallot.createdAt {
                let existingData = existing.eventId.id
                let incomingData = incomingBallot.eventId.id
                if !existingData.lexicographicallyPrecedes(incomingData) {
                    return false
                }
            }
        }

        state.ballotsByPubkey[response.responder] = incomingBallot
        return true
    }

    private func sanitizedSelectionIDs(from selectionIDs: [String], poll: PollEvent) -> [String] {
        switch poll.pollType {
        case .singleChoice:
            guard let firstValid = selectionIDs.first(where: { poll.containsOption($0) }) else {
                return []
            }
            return [firstValid]

        case .multipleChoice:
            var seen: Set<String> = []
            var sanitized: [String] = []
            for option in selectionIDs {
                guard poll.containsOption(option), !seen.contains(option) else { continue }
                seen.insert(option)
                sanitized.append(option)
            }
            return sanitized
        }
    }

    private func sanitizeSelections(from response: PollResponse, poll: PollEvent) -> [String] {
        sanitizedSelectionIDs(from: response.optionIds, poll: poll)
    }
}
