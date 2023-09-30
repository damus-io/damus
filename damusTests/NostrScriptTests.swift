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
    
    func read_bundle_file(name: String, ext: String) throws -> Data {
        let bundle = Bundle(for: type(of: self))
        guard let fileURL = bundle.url(forResource: name, withExtension: ext) else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        
        return try Data(contentsOf: fileURL)
    }
    
    func loadTestWasm() throws -> Data {
        return try read_bundle_file(name: "primal", ext: "wasm")
    }

    func load_bool_set_test_wasm() throws -> Data {
        return try read_bundle_file(name: "bool_setting", ext: "wasm")
    }
    
    func test_bool_set() throws {
        let data = try load_bool_set_test_wasm().bytes
        let pool = RelayPool(ndb: .empty)
        let script = NostrScript(pool: pool, data: data)
        let pk = Pubkey(hex: "32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245")!
        UserSettingsStore.pubkey = pk
        let key = pk_setting_key(pk, key: "nozaps")
        UserDefaults.standard.set(true, forKey: key)
        
        let load_err = script.load()
        XCTAssertNil(load_err)
        
        let res = script.run()
        switch res {
        case .finished:
            let set = UserDefaults.standard.bool(forKey: key)
            XCTAssertEqual(set, false)
        case .runtime_err: XCTAssert(false)
        case .suspend:
            XCTAssert(false)
            break
        }
    }

    /*
    func test_nostrscript() throws {
        let data = try loadTestWasm().bytes
        let pool = RelayPool()
        let script = NostrScript(pool: pool, data: data)
        
        let load_err = script.load()
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
        
        pool.connect(to: ["wss://cache0.primal.net/cache17"])
        
        self.wait(for: [resume_expected], timeout: 5.0)
    }
     */

}
