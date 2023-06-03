//
//  NostrScriptTests.swift
//  damusTests
//
//  Created by William Casarin on 2023-06-02.
//

import XCTest
@testable import damus

final class NostrScriptTests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }
    
    func loadTestWasm() throws -> Data {
        let bundle = Bundle(for: type(of: self))
        guard let fileURL = bundle.url(forResource: "primal", withExtension: "wasm") else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        
        return try Data(contentsOf: fileURL)
    }

    func test_nostrscript() throws {
        var data = try loadTestWasm().bytes
        let pool = RelayPool()
        let script = NostrScript(pool: pool)
        
        let load_err = script.load(wasm: &data)
        XCTAssertNil(load_err)
        
        let res = script.run()
        switch res {
        case .finished: XCTAssert(false)
        case .runtime_err: XCTAssert(false)
        case .suspend:
            XCTAssertEqual(script.waiting_on, .event("sidebar_trending"))
            break
        }
        
        let resume_expected = XCTestExpectation(description: "we got ")
        pool.register_handler(sub_id: "sidebar_trending") { (relay_id, conn) in
            if script.runstate?.exited == true {
                pool.disconnect()
                resume_expected.fulfill()
                return
            }
            
            guard case .nostr_event(let resp) = conn else {
                return
            }
            
            let with: NScriptResumeWith = .event(resp)
            guard let res = script.resume(with: with) else {
                return
            }
            
            switch res {
            case .finished: break
            case .runtime_err: XCTAssert(false)
            case .suspend: break
            }
        }
        
        pool.connect(to: ["wss://cache3.primal.net/cache15"])
        
        self.wait(for: [resume_expected], timeout: 10.0)
    }

    func testPerformanceExample() throws {
        // This is an example of a performance test case.
        self.measure {
            // Put the code you want to measure the time of here.
        }
    }

}
