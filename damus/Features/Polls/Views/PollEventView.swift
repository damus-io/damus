//
//  PollEventView.swift
//  damus
//
//  Created by ChatGPT on 2025-04-02.
//

import SwiftUI

struct PollEventView: View {
    let damus: DamusState
    let event: NostrEvent
    let poll: PollEvent
    let options: EventViewOptions

    @ObservedObject private var store: PollResultsStore

    init(damus: DamusState, event: NostrEvent, poll: PollEvent, options: EventViewOptions) {
        self.damus = damus
        self.event = event
        self.poll = poll
        self.options = options
        self.store = damus.polls
    }

    var body: some View {
        EventShell(state: damus, event: event, options: options) {
            PollEventCard(damusState: damus, poll: poll, store: store)
        }
    }
}

private struct PollEventCard: View {
    let damusState: DamusState
    let poll: PollEvent
    @ObservedObject var store: PollResultsStore

    @State private var selectedOptions: Set<String> = []
    @State private var isSubmitting: Bool = false
    @State private var errorMessage: String? = nil

    private var pollState: PollResultsStore.PollState? {
        store.state(for: poll.id)
    }

    private var ourSelections: [String] {
        pollState?.selections(for: damusState.pubkey) ?? []
    }

    private var hasVoted: Bool {
        pollState?.hasVoted(pubkey: damusState.pubkey) ?? false
    }

    private var isExpired: Bool {
        poll.isExpired(now: Date())
    }

    private var showResults: Bool {
        hasVoted || isExpired
    }

    private var canSubmit: Bool {
        guard !showResults else { return false }
        guard !isSubmitting else { return false }
        guard damusState.keypair.to_full() != nil else { return false }
        return !selectedOptions.isEmpty
    }

    private var expirationText: String? {
        guard let endsAt = poll.endsAt else { return nil }
        if isExpired {
            return NSLocalizedString("Poll closed", comment: "Label shown when the poll has ended.")
        } else {
            let relative = format_relative_time(endsAt)
            return String(format: NSLocalizedString("Ends %@", comment: "Label showing when the poll will end."), relative)
        }
    }

    private var totalVotes: Int {
        pollState?.totalVotes ?? 0
    }

    private var voterCount: Int {
        pollState?.voterCount ?? 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(poll.question)
                .font(.headline)

            if let expirationText {
                Text(expirationText)
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(poll.options) { option in
                    if showResults {
                        PollResultRow(
                            option: option,
                            poll: poll,
                            pollState: pollState,
                            isHighlighted: ourSelections.contains(option.id)
                        )
                    } else {
                        PollSelectionRow(
                            option: option,
                            isSelected: selectedOptions.contains(option.id),
                            pollType: poll.pollType
                        ) {
                            toggleSelection(for: option.id)
                        }
                    }
                }
            }

            if showResults {
                let voteSummary = summaryText()
                Text(voteSummary)
                    .font(.footnote)
                    .foregroundColor(.secondary)
            } else {
                if damusState.keypair.to_full() == nil {
                    Text(NSLocalizedString("Sign in with your private key to vote.", comment: "Message shown when the user cannot vote without a private key."))
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }

                Button(action: submitVote) {
                    if isSubmitting {
                        ProgressView()
                    } else {
                        Text(NSLocalizedString("Submit Vote", comment: "Button to submit a poll vote."))
                            .bold()
                    }
                }
                .buttonStyle(GradientButtonStyle(padding: 10))
                .disabled(!canSubmit)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundColor(.red)
            }
        }
        .padding(.vertical, 8)
        .onAppear {
            selectedOptions = Set(ourSelections)
            store.ensureResults(for: poll, network: damusState.nostrNetwork)
        }
        .onChange(of: ourSelections) { newValue in
            if showResults {
                selectedOptions = Set(newValue)
            }
        }
    }

    private func toggleSelection(for optionID: String) {
        guard !showResults else { return }
        switch poll.pollType {
        case .singleChoice:
            selectedOptions = [optionID]
        case .multipleChoice:
            if selectedOptions.contains(optionID) {
                selectedOptions.remove(optionID)
            } else {
                selectedOptions.insert(optionID)
            }
        }
    }

    private func submitVote() {
        guard !selectedOptions.isEmpty else { return }
        isSubmitting = true
        errorMessage = nil

        Task {
            let result = await store.submitVote(for: poll, selections: Array(selectedOptions), damusState: damusState)
            await MainActor.run {
                switch result {
                case .success:
                    selectedOptions = Set(ourSelections)
                case .failure(let error):
                    errorMessage = errorMessage(for: error)
                }
                isSubmitting = false
            }
        }
    }

    private func summaryText() -> String {
        if poll.pollType == .multipleChoice {
            return String(
                format: NSLocalizedString("Selections: %d • Voters: %d", comment: "Summary of poll results showing total selections and voter count."),
                totalVotes,
                voterCount
            )
        } else {
            return String(
                format: NSLocalizedString("Votes: %d", comment: "Summary of poll results showing the total number of votes."),
                voterCount
            )
        }
    }

    private func errorMessage(for error: PollResultsStore.PollVoteError) -> String {
        switch error {
        case .noKeypair:
            return NSLocalizedString("You need your private key to vote.", comment: "Error shown when the user lacks a private key.")
        case .noSelection:
            return NSLocalizedString("Select at least one option before voting.", comment: "Error shown when no option is selected.")
        case .pollClosed:
            return NSLocalizedString("This poll has already ended.", comment: "Error shown when voting on a closed poll.")
        case .invalidSelection:
            return NSLocalizedString("Your selection is not valid for this poll.", comment: "Error shown when the selection is invalid.")
        case .eventBuildFailed:
            return NSLocalizedString("Could not create your vote. Please try again.", comment: "Generic error shown when vote event creation fails.")
        }
    }
}

private struct PollSelectionRow: View {
    let option: PollOption
    let isSelected: Bool
    let pollType: PollType
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: selectionIconName)
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                Text(option.label)
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var selectionIconName: String {
        switch pollType {
        case .singleChoice:
            return isSelected ? "largecircle.fill.circle" : "circle"
        case .multipleChoice:
            return isSelected ? "checkmark.square.fill" : "square"
        }
    }
}

private struct PollResultRow: View {
    let option: PollOption
    let poll: PollEvent
    let pollState: PollResultsStore.PollState?
    let isHighlighted: Bool

    private var votesForOption: Int {
        pollState?.tallies[option.id] ?? 0
    }

    private var totalVotes: Int {
        max(pollState?.totalVotes ?? 0, 0)
    }

    private var progress: Double {
        guard totalVotes > 0 else { return 0 }
        return Double(votesForOption) / Double(totalVotes)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(option.label)
                    .fontWeight(isHighlighted ? .semibold : .regular)
                Spacer()
                Text(voteCountLabel())
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }

            ProgressView(value: progress)
                .tint(isHighlighted ? .accentColor : .blue)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHighlighted ? Color.accentColor.opacity(0.1) : Color.secondary.opacity(0.08))
        )
    }

    private func voteCountLabel() -> String {
        if poll.pollType == .multipleChoice {
            return String(format: NSLocalizedString("%d selections", comment: "Number of selections for a poll option in multi-choice polls."), votesForOption)
        } else {
            return String(format: NSLocalizedString("%d votes", comment: "Number of votes for a poll option."), votesForOption)
        }
    }
}
