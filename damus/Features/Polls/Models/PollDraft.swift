//
//  PollDraft.swift
//  damus
//
//  Created by ChatGPT on 2025-04-02.
//

import Foundation

struct PollDraftOption: Identifiable, Equatable {
    let id: UUID
    var text: String
}

struct PollDraft: Equatable {
    var options: [PollDraftOption]
    var pollType: PollType
    var endsAt: Date?

    static let minimumOptions: Int = 2
    static let maximumOptions: Int = 6

    static func makeDefault() -> PollDraft {
        PollDraft(
            options: (0..<PollDraft.minimumOptions).map { _ in PollDraftOption(id: UUID(), text: "") },
            pollType: .singleChoice,
            endsAt: nil
        )
    }

    mutating func addOption() {
        guard options.count < PollDraft.maximumOptions else { return }
        options.append(PollDraftOption(id: UUID(), text: ""))
    }

    mutating func removeOption(id: UUID) {
        guard options.count > PollDraft.minimumOptions else { return }
        options.removeAll { $0.id == id }
    }

    mutating func ensureMinimumOptions() {
        if options.count < PollDraft.minimumOptions {
            let missing = PollDraft.minimumOptions - options.count
            for _ in 0..<missing {
                options.append(PollDraftOption(id: UUID(), text: ""))
            }
        }
    }

    var normalizedOptionLabels: [String] {
        options
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

