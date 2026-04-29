//
//  ThreadModelTests.swift
//  damus
//
//  Created by Daniel D’Aquino on 2025-08-25.
//


import XCTest
@testable import damus

@MainActor
final class ThreadModelTests: XCTestCase {
    var damusState: DamusState? = nil
    
    override func setUp() async throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
        damusState = generate_test_damus_state(mock_profile_info: nil)

        let notesJSONL = getTestNotesJSONL()

        for noteText in notesJSONL.split(separator: "\n") {
            let _ = damusState!.ndb.process_event("[\"EVENT\",\"subid\",\(String(noteText))]")
        }

        // Give NDB's async ingester time to commit all pre-loaded events to the database
        // before any test begins subscribing or querying.
        //
        // NDB processes events asynchronously via a background ingester thread.
        // 200 ms is a generous budget consistent with the 100 ms used in testDirectNdbStreaming
        // in NostrNetworkManagerTests and observed to be sufficient on CI hardware.
        try await Task.sleep(for: .milliseconds(200))
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
    
    /// Tests loading up a thread and checking if the repost count loads as expected.
    func testActionBarModel() async throws {
        guard let damusState else {
            XCTFail("DamusState is nil, test is misconfigured")
            return
        }
        try await damusState.nostrNetwork.userRelayList.set(userRelayList: NIP65.RelayList())
        await damusState.nostrNetwork.connect()
        
        let testNoteJson = """
{"content":"https://smartflowsocial.s3.us-east-1.amazonaws.com/clients/cm7kdrwdk0000qyu6fwtd96ui/0cab65a9-0142-48e3-abd7-94d20e30d3b2.jpg\n\n","pubkey":"71ecabd8b6b33548e075ff01b31568ffda19d0ac2788067d99328c6de4885975","tags":[["t","meme"],["t","memes"],["t","memestr"],["t","plebchain"]],"created_at":1755694800,"id":"64b26d0a587f5f894470e1e4783756b4d8ba971226de975ee30ac1b69970d5a1","kind":1,"sig":"c000794da8c4f7549b546630b16ed17f6edc0af0269b8c46ce14f5b1937431e7575b78351bc152007ebab5720028e5fe4b738f99e8887f273d35dd2217d1cc3d"}
"""
        let note = NostrEvent.owned_from_json(json: testNoteJson)!
        let threadModel = ThreadModel(event: note, damus_state: damusState)
        threadModel.subscribe()
        let actionBarModel = make_actionbar_model(ev: note.id, damus: damusState)

        // Poll for up to 10 seconds (20 attempts × 500 ms) for the subscription pipeline
        // to deliver all boost events and populate the action bar model.
        //
        // Using a bounded loop instead of `while true` ensures the test always fails with
        // a descriptive assertion rather than timing out via XCTestExpectation.
        // 20 attempts × 500 ms = 10 s matches the original XCTestExpectation timeout.
        let maxPollingAttempts = 20
        for _ in 0..<maxPollingAttempts {
            try await Task.sleep(for: .milliseconds(500))
            await actionBarModel.update(damus: damusState, evid: note.id)
            if actionBarModel.boosts >= 5 {
                break
            }
        }
        XCTAssertEqual(actionBarModel.boosts, 5)
    }
}
