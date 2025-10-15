import XCTest
import SwiftUI
@testable import damus

final class PollEventViewFactoryTests: XCTestCase {

    @MainActor
    func testFactoryProducesPollViewAfterRegistration() throws {
        let originalBuilder = PollEventViewFactory.builder
        defer { PollEventViewFactory.builder = originalBuilder }

        PollEventViewFactory.registerAppBuilder()

        let damusState = generate_test_damus_state(mock_profile_info: nil)
        let event = makePollEvent(state: damusState)

        let poll = try XCTUnwrap(PollEvent(event: event))
        damusState.polls.registerPollEvent(event)

        let view = PollEventViewFactory.makePollEventView(damus: damusState, event: event, poll: poll, options: [])
        XCTAssertNotNil(view, "PollEventViewFactory should return a view once the app builder is registered.")
    }

    private func makePollEvent(state: DamusState) -> NostrEvent {
        let pollDraft = PollDraft(
            options: [
                PollDraftOption(id: UUID(), text: "Apples"),
                PollDraftOption(id: UUID(), text: "Bananas"),
                PollDraftOption(id: UUID(), text: "Cherries")
            ],
            pollType: .singleChoice,
            endsAt: Date().addingTimeInterval(900)
        )

        let post = build_poll_post(
            state: state,
            post: NSAttributedString(string: "What's your favourite fruit?"),
            pollDraft: pollDraft
        )

        return post!.to_event(keypair: test_keypair_full)!
    }
}
