//
//  PollVoteBuilder.swift
//  damus
//
//  Created by ChatGPT on 2025-04-02.
//

import Foundation

struct PollVoteBuilder {
    static func makeResponseEvent(
        poll: PollEvent,
        selections: [String],
        keypair: FullKeypair,
        timestamp: UInt32? = nil
    ) -> NostrEvent? {
        let sanitizedSelections = sanitize(selections: selections, for: poll)
        guard !sanitizedSelections.isEmpty else { return nil }

        var tags: [[String]] = []
        tags.append(["e", poll.id.hex()])

        for optionId in sanitizedSelections {
            tags.append(["response", optionId])
        }

        if !poll.relayHints.isEmpty {
            for relay in poll.relayHints {
                tags.append(["relay", relay.absoluteString])
            }
        }

        let createdAt = timestamp ?? UInt32(Date().timeIntervalSince1970)
        return NostrEvent(
            content: "",
            keypair: keypair.to_keypair(),
            kind: NostrKind.poll_response.rawValue,
            tags: tags,
            createdAt: createdAt
        )
    }

    private static func sanitize(selections: [String], for poll: PollEvent) -> [String] {
        switch poll.pollType {
        case .singleChoice:
            return selections.first(where: { poll.containsOption($0) }).map { [$0] } ?? []
        case .multipleChoice:
            var seen: Set<String> = []
            var sanitized: [String] = []
            for option in selections {
                guard poll.containsOption(option), !seen.contains(option) else { continue }
                seen.insert(option)
                sanitized.append(option)
            }
            return sanitized
        }
    }
}

