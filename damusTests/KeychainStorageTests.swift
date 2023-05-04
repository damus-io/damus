//
//  KeychainStorageTests.swift
//  damusTests
//
//  Created by Bryan Montz on 5/3/23.
//

import XCTest
@testable import damus
import Security

final class KeychainStorageTests: XCTestCase {
    @KeychainStorage(account: "test-keyname")
    var secret: String?

    override func tearDownWithError() throws {
        secret = nil
    }

    func testWriteToKeychain() throws {
        // write a secret to the keychain using the property wrapper's setter
        secret = "super-secure-key"
        
        // verify it exists in the keychain using the property wrapper's getter
        XCTAssertEqual(secret, "super-secure-key")
        
        // verify it exists in the keychain directly
        let query = [
            kSecAttrService: "damus",
            kSecAttrAccount: "test-keyname",
            kSecClass: kSecClassGenericPassword,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ] as [CFString: Any] as CFDictionary
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query, &result)
        XCTAssertEqual(status, errSecSuccess)
        
        let data = try XCTUnwrap(result as? Data)
        let the_secret = String(data: data, encoding: .utf8)
        
        XCTAssertEqual(the_secret, "super-secure-key")
    }

}
