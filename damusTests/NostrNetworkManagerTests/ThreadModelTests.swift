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
    
    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
        damusState = generate_test_damus_state(mock_profile_info: nil)

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
    func testActionBarModel() async throws {
        guard let damusState else {
            XCTFail("DamusState is nil, test is misconfigured")
            return
        }
        try! await damusState.nostrNetwork.userRelayList.set(userRelayList: NIP65.RelayList())
        await damusState.nostrNetwork.connect()
        
        let testNoteJson = """
{"content":"https://smartflowsocial.s3.us-east-1.amazonaws.com/clients/cm7kdrwdk0000qyu6fwtd96ui/0cab65a9-0142-48e3-abd7-94d20e30d3b2.jpg\n\n","pubkey":"71ecabd8b6b33548e075ff01b31568ffda19d0ac2788067d99328c6de4885975","tags":[["t","meme"],["t","memes"],["t","memestr"],["t","plebchain"]],"created_at":1755694800,"id":"64b26d0a587f5f894470e1e4783756b4d8ba971226de975ee30ac1b69970d5a1","kind":1,"sig":"c000794da8c4f7549b546630b16ed17f6edc0af0269b8c46ce14f5b1937431e7575b78351bc152007ebab5720028e5fe4b738f99e8887f273d35dd2217d1cc3d"}
"""
        let testShouldComplete = XCTestExpectation(description: "Test should complete")
        Task {
            let note = NostrEvent.owned_from_json(json: testNoteJson)!
            let threadModel = ThreadModel(event: note, damus_state: damusState)
            threadModel.subscribe()
            let actionBarModel = make_actionbar_model(ev: note.id, damus: damusState)
            while true {
                try await Task.sleep(nanoseconds: 500_000_000)
                await actionBarModel.update(damus: damusState, evid: note.id)
                if actionBarModel.boosts >= 5 {
                    break
                }
            }
            XCTAssertEqual(actionBarModel.boosts, 5)
            testShouldComplete.fulfill()
        }
        await fulfillment(of: [testShouldComplete], timeout: 10.0)
    }

    // MARK: - ThreadEventMap cycle detection tests

    /// Helper to create a NostrEvent from JSON with a specific id and optional reply tag.
    /// Uses NdbNote.owned_from_json which does not verify signatures, allowing crafted test events.
    private func makeEvent(idHex: String, replyToHex: String? = nil, createdAt: Int = 1700000000) -> NostrEvent? {
        let pubkeyHex = "0000000000000000000000000000000000000000000000000000000000000001"
        let sigHex = String(repeating: "0", count: 128)
        var tagsJson = "[]"
        if let replyToHex {
            tagsJson = """
            [["e","\(replyToHex)","","root"],["e","\(replyToHex)","","reply"]]
            """
        }
        let json = """
        {"id":"\(idHex)","pubkey":"\(pubkeyHex)","created_at":\(createdAt),"kind":1,"tags":\(tagsJson),"content":"test","sig":"\(sigHex)"}
        """
        return NostrEvent.owned_from_json(json: json)
    }

    /// Regression test: parent_events must terminate when reply references form a cycle (A→B→A).
    /// Before the fix, this would loop infinitely. After the fix, the visited set breaks the cycle.
    func testThreadEventMap_parentEvents_terminatesOnCycle() throws {
        let idA = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        let idB = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

        // A replies to B, B replies to A — forming a cycle
        guard let eventA = makeEvent(idHex: idA, replyToHex: idB, createdAt: 1700000001),
              let eventB = makeEvent(idHex: idB, replyToHex: idA, createdAt: 1700000002) else {
            XCTFail("Failed to create test events")
            return
        }

        var map = ThreadEventMap()
        map.add(event: eventA)
        map.add(event: eventB)

        // Without cycle detection this would hang forever.
        // With the fix, it should return a finite list (at most 1 parent).
        let parentsOfA = map.parent_events(of: eventA)
        XCTAssertLessThanOrEqual(parentsOfA.count, 1, "parent_events should terminate, returning at most the direct parent")

        let parentsOfB = map.parent_events(of: eventB)
        XCTAssertLessThanOrEqual(parentsOfB.count, 1, "parent_events should terminate, returning at most the direct parent")
    }

    /// Regression test: recursive_child_events must terminate when reply references form a cycle (A→B→A).
    /// Before the fix, this would loop infinitely. After the fix, the visited set breaks the cycle.
    func testThreadEventMap_recursiveChildEvents_terminatesOnCycle() throws {
        let idA = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        let idB = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

        // A replies to B, B replies to A — both are each other's child AND parent
        guard let eventA = makeEvent(idHex: idA, replyToHex: idB, createdAt: 1700000001),
              let eventB = makeEvent(idHex: idB, replyToHex: idA, createdAt: 1700000002) else {
            XCTFail("Failed to create test events")
            return
        }

        var map = ThreadEventMap()
        map.add(event: eventA)
        map.add(event: eventB)

        // Without cycle detection this would recurse infinitely.
        // With the fix, it should return a finite set.
        let childrenOfA = map.recursive_child_events(of: eventA)
        XCTAssertLessThanOrEqual(childrenOfA.count, 1, "recursive_child_events should terminate, finding at most the direct child")

        let childrenOfB = map.recursive_child_events(of: eventB)
        XCTAssertLessThanOrEqual(childrenOfB.count, 1, "recursive_child_events should terminate, finding at most the direct child")
    }
}
