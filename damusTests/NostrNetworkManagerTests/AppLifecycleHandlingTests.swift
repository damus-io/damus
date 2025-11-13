//
//  AppLifecycleHandlingTests.swift
//  damus
//
//  Created by Daniel D’Aquino on 2025-11-06.
//

import XCTest
@testable import damus


class AppLifecycleHandlingTests: XCTestCase {
    
    func getTestNotesJSONL() -> String {
        // Get the path for the test_notes.jsonl file in the same folder as this test file
        let testBundle = Bundle(for: type(of: self))
        let fileURL = testBundle.url(forResource: "test_notes", withExtension: "jsonl")!

        // Load the contents of the file
        return try! String(contentsOf: fileURL, encoding: .utf8)
    }
    
    /// Tests for some race conditions between the app closing down and streams opening throughout the app
    /// See https://github.com/damus-io/damus/issues/3245 for more context.
    ///
    /// **Note:** Time delays are intentionally added because we actually want to provoke possible race conditions,
    /// so using proper waiting mechanisms would defeat the purpose of the test.
    func testAppLifecycleRaceConditions() async throws {
        let damusState = generate_test_damus_state(mock_profile_info: nil)
        
        let notesJSONL = getTestNotesJSONL()
        for noteText in notesJSONL.split(separator: "\n") {
            let _ = damusState.ndb.processEvent("[\"EVENT\",\"subid\",\(String(noteText))]")
        }
        
        // Give some time ndb some time to fill up
        try? await Task.sleep(for: .milliseconds(2000))
        
        
        
        // Start measuring the time elapsed for debugging
        let startTime = CFAbsoluteTimeGetCurrent()
        func getElapsedTimeMiliseconds() -> String {
            return "\((CFAbsoluteTimeGetCurrent() - startTime) * 1000) ms"
        }
        
        
        Task.detached {
            for _ in 0...10000 {
                try await Task.sleep(for: .milliseconds(Int.random(in: 0...10)))
                print("APP_LIFECYCLE_TEST: About to close Ndb. Elapsed time: \(getElapsedTimeMiliseconds())")
                damusState.ndb.close()
                print("APP_LIFECYCLE_TEST: Closed Ndb. Elapsed time: \(getElapsedTimeMiliseconds())")
                print("APP_LIFECYCLE_TEST: Reopening Ndb. Elapsed time: \(getElapsedTimeMiliseconds())")
                _ = damusState.ndb.reopen()
                print("APP_LIFECYCLE_TEST: Reopened Ndb. Elapsed time: \(getElapsedTimeMiliseconds())")
                
            }
        }
        for _ in 0...10000 {
            do {
                try await Task.sleep(for: .milliseconds(Int.random(in: 0...10)))
                print("APP_LIFECYCLE_TEST: Starting new query. Elapsed time: \(getElapsedTimeMiliseconds())")
                guard let txn = NdbTxn(ndb: damusState.ndb) else { continue }
                _ = try damusState.ndb.query(with: txn, filters: [try NdbFilter(from: NostrFilter(kinds: [.text], limit: 1000))], maxResults: 500)
            }
            catch {
                print("APP_LIFECYCLE_TEST: Query error: \(error). Elapsed time: \(getElapsedTimeMiliseconds())")
            }
            print("APP_LIFECYCLE_TEST: Finished query. Elapsed time: \(getElapsedTimeMiliseconds())")
        }
    }
}
