import XCTest
@testable import damus

final class PollTests: XCTestCase {

    func testPollEventParsing() {
        let pollEvent = makePollEvent(
            question: "Favorite fruit?",
            optionTuples: [
                ("opt1", "Apples"),
                ("opt2", "Bananas")
            ],
            pollType: .singleChoice,
            endsAt: UInt32(Date().addingTimeInterval(3600).timeIntervalSince1970)
        )

        guard let poll = PollEvent(event: pollEvent) else {
            XCTFail("Failed to parse poll event")
            return
        }

        XCTAssertEqual(poll.question, "Favorite fruit?")
        XCTAssertEqual(poll.options.count, 2)
        XCTAssertEqual(poll.options.first?.id, "opt1")
        XCTAssertEqual(poll.pollType, .singleChoice)
        XCTAssertNotNil(poll.endsAt)
    }

    func testPollResultsStoreSubmitVote() {
        let pollEvent = makePollEvent(
            question: "Best season",
            optionTuples: [
                ("spring", "Spring"),
                ("summer", "Summer"),
                ("fall", "Fall"),
                ("winter", "Winter")
            ],
            pollType: .singleChoice,
            endsAt: UInt32(Date().addingTimeInterval(7200).timeIntervalSince1970)
        )

        guard let poll = PollEvent(event: pollEvent) else {
            XCTFail("Failed to parse poll event")
            return
        }

        let damusState = generate_test_damus_state(mock_profile_info: nil)

        let store = PollResultsStore()
        store.registerPollEvent(pollEvent)

        let result = store.submitVote(for: poll, selections: ["summer"], damusState: damusState)

        switch result {
        case .success:
            break
        case .failure(let error):
            XCTFail("Vote submission failed with error: \(error)")
        }

        guard let state = store.state(for: poll.id) else {
            XCTFail("Poll state not found")
            return
        }

        XCTAssertEqual(state.voterCount, 1)
        XCTAssertEqual(state.tallies["summer"], 1)
        XCTAssertTrue(state.hasVoted(pubkey: damusState.pubkey))
    }

    // MARK: - Helpers

    private func makePollEvent(question: String, optionTuples: [(String, String)], pollType: PollType, endsAt: UInt32?) -> NostrEvent {
        let tags: [[String]] = optionTuples.map { ["option", $0.0, $0.1] }
            + [["polltype", pollType.rawValue]]
            + (endsAt.map { [["endsAt", String($0)]] } ?? [])

        return NostrEvent(
            content: question,
            keypair: test_keypair,
            kind: NostrKind.poll.rawValue,
            tags: tags
        )!
    }
}
