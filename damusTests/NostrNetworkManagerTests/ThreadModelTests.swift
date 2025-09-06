//
//  ThreadModelTests.swift
//  damus
//
//  Created by Daniel D’Aquino on 2025-08-25.
//


import XCTest
@testable import damus

final class ThreadModelTests: XCTestCase {
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
    
    /// Tests loading up a thread and checking if the repost count loads as expected.
    func testActionBarModel() throws {
        let testNoteJson = """
{"content":"https://smartflowsocial.s3.us-east-1.amazonaws.com/clients/cm7kdrwdk0000qyu6fwtd96ui/0cab65a9-0142-48e3-abd7-94d20e30d3b2.jpg\n\n","pubkey":"71ecabd8b6b33548e075ff01b31568ffda19d0ac2788067d99328c6de4885975","tags":[["t","meme"],["t","memes"],["t","memestr"],["t","plebchain"]],"created_at":1755694800,"id":"64b26d0a587f5f894470e1e4783756b4d8ba971226de975ee30ac1b69970d5a1","kind":1,"sig":"c000794da8c4f7549b546630b16ed17f6edc0af0269b8c46ce14f5b1937431e7575b78351bc152007ebab5720028e5fe4b738f99e8887f273d35dd2217d1cc3d"}
"""
        let testShouldComplete = XCTestExpectation(description: "Test should complete")
        Task {
            let note = NostrEvent.owned_from_json(json: testNoteJson)!
            let threadModel = await ThreadModel(event: note, damus_state: damusState!)
            await threadModel.subscribe()
            let actionBarModel = make_actionbar_model(ev: note.id, damus: damusState!)
            while true {
                try await Task.sleep(nanoseconds: 500_000_000)
                actionBarModel.update(damus: damusState!, evid: note.id)
                if actionBarModel.boosts >= 5 {
                    break
                }
            }
            XCTAssertEqual(actionBarModel.boosts, 5)
            testShouldComplete.fulfill()
        }
        wait(for: [testShouldComplete], timeout: 10.0)
    }
}
