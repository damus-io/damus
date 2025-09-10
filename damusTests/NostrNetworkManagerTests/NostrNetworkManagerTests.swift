//
//  NostrNetworkManagerTests.swift
//  damus
//
//  Created by Daniel D'Aquino on 2025-08-22.
//

import XCTest
@testable import damus


class NostrNetworkManagerTests: XCTestCase {
    var damusState: DamusState? = nil
    
    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
        damusState = generate_test_damus_state(mock_profile_info: nil)
        try! damusState?.nostrNetwork.userRelayList.set(userRelayList: NIP65.RelayList())
        damusState?.nostrNetwork.connect()

        let notesJSONL = getTestNotesJSONL()

        for noteText in notesJSONL.split(separator: "\n") {
            let _ = damusState!.ndb.process_event("[\"EVENT\",\"subid\",\(String(noteText))]")
        }
    }
    
    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        damusState = nil
    }
    
    func getTestNotesJSONL() -> String {
        // Get the path for the test_notes.jsonl file in the same folder as this test file
        let testBundle = Bundle(for: type(of: self))
        let fileURL = testBundle.url(forResource: "test_notes", withExtension: "jsonl")!

        // Load the contents of the file
        return try! String(contentsOf: fileURL, encoding: .utf8)
    }
    
    func ensureSubscribeGetsAllExpectedNotes(filter: NostrFilter, expectedCount: Int) {
        let endOfStream = XCTestExpectation(description: "Stream should receive EOSE")
        let gotAtLeastExpectedCount = XCTestExpectation(description: "Stream should receive at least the expected number of items")
        var receivedCount = 0
        var eventIds: Set<NoteId> = []
        Task {
            for await item in self.damusState!.nostrNetwork.reader.subscribe(filters: [filter]) {
                switch item {
                case .event(let lender):
                    try? lender.borrow { event in
                        receivedCount += 1
                        if eventIds.contains(event.id) {
                            XCTFail("Got duplicate event ID: \(event.id) ")
                        }
                        eventIds.insert(event.id)
                    }
                    if receivedCount == expectedCount {
                        gotAtLeastExpectedCount.fulfill()
                    }
                case .eose:
                    // End of stream, break out of the loop
                    endOfStream.fulfill()
                }
            }
        }
        wait(for: [endOfStream, gotAtLeastExpectedCount], timeout: 10.0)
        XCTAssertEqual(receivedCount, expectedCount, "Event IDs: \(eventIds.map({ $0.hex() }))")
    }
    
    /// Tests to ensure that subscribing gets the correct amount of events
    ///
    /// ## Implementation notes:
    ///
    /// To create a new scenario, `nak` can be used as a reference:
    /// 1. `cd` into the folder where the `test_notes.jsonl` file is
    /// 2. Run `nak serve --events test_notes.jsonl`
    /// 3. On a separate terminal, run `nak` commands with the desired filter against the local relay, and get the line count. Example:
    /// ```
    /// nak req --kind 1 ws://localhost:10547 | wc -l
    /// ```
    func testNdbSubscription() {
        ensureSubscribeGetsAllExpectedNotes(filter: NostrFilter(kinds: [.text]), expectedCount: 57)
        ensureSubscribeGetsAllExpectedNotes(filter: NostrFilter(authors: [Pubkey(hex: "32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245")!]), expectedCount: 22)
        ensureSubscribeGetsAllExpectedNotes(filter: NostrFilter(kinds: [.boost], referenced_ids: [NoteId(hex: "64b26d0a587f5f894470e1e4783756b4d8ba971226de975ee30ac1b69970d5a1")!]), expectedCount: 5)
        ensureSubscribeGetsAllExpectedNotes(filter: NostrFilter(kinds: [.text, .boost, .zap], referenced_ids: [NoteId(hex: "64b26d0a587f5f894470e1e4783756b4d8ba971226de975ee30ac1b69970d5a1")!], limit: 500), expectedCount: 5)
        ensureSubscribeGetsAllExpectedNotes(filter: NostrFilter(kinds: [.text], limit: 10), expectedCount: 10)
        ensureSubscribeGetsAllExpectedNotes(filter: NostrFilter(kinds: [.text], until: UInt32(Date.now.timeIntervalSince1970), limit: 10), expectedCount: 10)
    }
}
