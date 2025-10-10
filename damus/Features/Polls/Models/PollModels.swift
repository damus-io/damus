//
//  PollModels.swift
//  damus
//
//  Created by ChatGPT on 2025-04-02.
//

import Foundation

enum PollType: String {
    case singleChoice = "singlechoice"
    case multipleChoice = "multiplechoice"

    static var `default`: PollType { .singleChoice }
}

struct PollOption: Identifiable, Hashable {
    let id: String
    let label: String
}

struct PollEvent {
    let id: NoteId
    let author: Pubkey
    let createdAt: UInt32
    let question: String
    let options: [PollOption]
    let pollType: PollType
    let relayHints: [RelayURL]
    let endsAt: UInt32?

    private let optionIdSet: Set<String>

    init?(event: NostrEvent) {
        guard event.known_kind == .poll else { return nil }

        var options: [PollOption] = []
        var optionIds: Set<String> = []
        var relayHints: [RelayURL] = []
        var pollType: PollType = .default
        var endsAt: UInt32? = nil

        for tag in event.tags {
            guard tag.count >= 2 else { continue }
            var iterator = tag.makeIterator()
            guard let keyElem = iterator.next() else { continue }

            switch keyElem.string() {
            case "option":
                guard tag.count >= 3,
                      let idElem = iterator.next(),
                      let labelElem = iterator.next()
                else { continue }
                let optionId = idElem.string()
                let optionLabel = labelElem.string()
                guard !optionId.isEmpty, !optionLabel.isEmpty, !optionIds.contains(optionId) else { continue }
                optionIds.insert(optionId)
                options.append(PollOption(id: optionId, label: optionLabel))

            case "relay":
                guard let relayElem = iterator.next(),
                      let relay = RelayURL(relayElem.string())
                else { continue }
                if !relayHints.contains(relay) {
                    relayHints.append(relay)
                }

            case "polltype":
                guard let typeElem = iterator.next() else { continue }
                pollType = PollType(rawValue: typeElem.string()) ?? .default

            case "endsAt":
                guard let endsElem = iterator.next() else { continue }
                if let raw = endsElem.u64() {
                    if raw > UInt64(UInt32.max) {
                        endsAt = UInt32.max
                    } else {
                        endsAt = UInt32(raw)
                    }
                }

            default:
                continue
            }
        }

        guard options.count >= 2 else { return nil }

        self.id = event.id
        self.author = event.pubkey
        self.createdAt = event.created_at
        self.question = event.content
        self.options = options
        self.pollType = pollType
        self.relayHints = relayHints
        self.endsAt = endsAt
        self.optionIdSet = optionIds
    }

    func containsOption(_ optionId: String) -> Bool {
        optionIdSet.contains(optionId)
    }

    func isExpired(at timestamp: UInt32) -> Bool {
        guard let endsAt else { return false }
        return timestamp > endsAt
    }

    func isExpired(now: Date = .now) -> Bool {
        guard let endsAt else { return false }
        return UInt32(now.timeIntervalSince1970) > endsAt
    }
}

struct PollResponse {
    let pollId: NoteId
    let responseId: NoteId
    let responder: Pubkey
    let createdAt: UInt32
    let optionIds: [String]

    init?(event: NostrEvent) {
        guard event.known_kind == .poll_response else { return nil }

        guard let pollReference = event.referenced_ids.first(where: { ref in
            if case .event = ref {
                return true
            }
            return false
        }),
        case .event(let pollId) = pollReference
        else {
            return nil
        }

        var responses: [String] = []
        for tag in event.tags {
            guard tag.count >= 2 else { continue }
            var iterator = tag.makeIterator()
            guard let keyElem = iterator.next(), keyElem.string() == "response",
                  let responseElem = iterator.next()
            else {
                continue
            }
            let optionId = responseElem.string()
            guard !optionId.isEmpty else { continue }
            responses.append(optionId)
        }

        guard !responses.isEmpty else { return nil }

        self.pollId = pollId
        self.responseId = event.id
        self.responder = event.pubkey
        self.createdAt = event.created_at
        self.optionIds = responses
    }
}

