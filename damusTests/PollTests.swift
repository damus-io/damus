import XCTest
@testable import damus

final class PollTests: XCTestCase {

    @MainActor
    override func tearDown() {
        PollEventViewFactory.builder = { _, _, _, _ in nil }
        super.tearDown()
    }

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

    @MainActor
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

        let store: PollResultsStore = MainActor.assumeIsolated { PollResultsStore() }
        store.registerPollEvent(pollEvent)

        let result = store.submitVote(for: poll, selections: ["summer"], context: damusState)

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

    @MainActor
    func testEnsureResultsSubscribesAndProcessesResponses() async throws {
        let pollEvent = makePollEvent(
            question: "Best snack?",
            optionTuples: [
                ("chips", "Chips"),
                ("choco", "Chocolate")
            ],
            pollType: .singleChoice,
            endsAt: nil
        )

        let store = PollResultsStore()
        guard let poll = PollEvent(event: pollEvent) else {
            XCTFail("Failed to parse poll event")
            return
        }

        store.registerPollEvent(pollEvent)

        let network = MockPollNetwork()
        store.ensureResults(for: poll, network: network)

        XCTAssertEqual(network.subscribeCalls.count, 1)
        XCTAssertEqual(network.subscribeCalls.first?.subId, "poll-\(poll.id.hex())")

        let responseEvent = NostrEvent(
            content: "",
            keypair: test_keypair,
            kind: NostrKind.poll_response.rawValue,
            tags: [
                ["e", poll.id.hex()],
                ["response", "choco"]
            ]
        )!

        guard let handler = network.subscribeCalls.first?.handler else {
            XCTFail("Expected subscription handler to be captured")
            return
        }

        handler(.event(network.subscribeCalls.first!.subId, responseEvent))

        // Allow the asynchronous Task in ensureResults to process on the main actor.
        await Task.yield()

        XCTAssertTrue(store.hasVoted(pollId: poll.id, pubkey: responseEvent.pubkey))
        XCTAssertEqual(store.selections(for: poll.id, pubkey: responseEvent.pubkey), ["choco"])
    }

    @MainActor
    func testSubmitVoteUsesVotingContextNetwork() throws {
        let pollEvent = makePollEvent(
            question: "Best season",
            optionTuples: [
                ("spring", "Spring"),
                ("summer", "Summer")
            ],
            pollType: .singleChoice,
            endsAt: nil
        )

        let store = PollResultsStore()
        guard let poll = PollEvent(event: pollEvent) else {
            XCTFail("Failed to parse poll event")
            return
        }

        store.registerPollEvent(pollEvent)

        let network = MockPollNetwork()
        let context = MockVotingContext(
            keypair: test_keypair_full.to_keypair(),
            pollNetwork: network
        )

        let result = store.submitVote(for: poll, selections: ["summer"], context: context)
        switch result {
        case .success:
            break
        case .failure(let error):
            XCTFail("Vote submission failed with error: \(error)")
        }

        XCTAssertEqual(network.sendCalls.count, 1)
        XCTAssertEqual(network.sendCalls.first?.event.kind, NostrKind.poll_response.rawValue)
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

    private final class MockPollNetwork: PollResponseNetworking {
        struct SubscribeCall {
            let poll: PollEvent
            let subId: String
            let handler: (NostrResponse) -> Void
        }

        struct SendCall {
            let event: NostrEvent
            let relayHints: [RelayURL]?
        }

        private(set) var subscribeCalls: [SubscribeCall] = []
        private(set) var sendCalls: [SendCall] = []

        func subscribeToPollResponses(poll: PollEvent, subId: String, handler: @escaping (NostrResponse) -> Void) {
            subscribeCalls.append(SubscribeCall(poll: poll, subId: subId, handler: handler))
        }

        func sendPollResponseEvent(_ event: NostrEvent, relayHints: [RelayURL]?) {
            sendCalls.append(SendCall(event: event, relayHints: relayHints))
        }
    }

    private struct MockVotingContext: PollVotingContext {
        let keypair: Keypair
        let pollNetwork: PollResponseNetworking
    }
}
