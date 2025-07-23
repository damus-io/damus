//
//  KeychainStorage.swift
//  damus
//
//  Created by Bryan Montz on 5/2/23.
//

import Foundation
import Security

@propertyWrapper struct KeychainStorage {
    let account: String
    private let service = "damus"
    
    var wrappedValue: String? {
        get {
            let query = [
                kSecAttrService: service,
                kSecAttrAccount: account,
                kSecClass: kSecClassGenericPassword,
                kSecReturnData: true,
                kSecMatchLimit: kSecMatchLimitOne
            ] as [CFString: Any] as CFDictionary
            
            var result: AnyObject?
            let status = SecItemCopyMatching(query, &result)
            
            if status == errSecSuccess, let data = result as? Data {
                return String(data: data, encoding: .utf8)
            } else {
                return nil
            }
        }
        set {
            if let newValue {
                let query = [
                    kSecAttrService: service,
                    kSecAttrAccount: account,
                    kSecClass: kSecClassGenericPassword,
                    kSecValueData: newValue.data(using: .utf8) as Any
                ] as [CFString: Any] as CFDictionary
                
                var status = SecItemAdd(query, nil)
                
                if status == errSecDuplicateItem {
                    let query = [
                        kSecAttrService: service,
                        kSecAttrAccount: account,
                        kSecClass: kSecClassGenericPassword
                    ] as [CFString: Any] as CFDictionary
                    
                    let updates = [
                        kSecValueData: newValue.data(using: .utf8) as Any
                    ] as CFDictionary
                    
                    status = SecItemUpdate(query, updates)
                }
            } else {
                let query = [
                    kSecAttrService: service,
                    kSecAttrAccount: account,
                    kSecClass: kSecClassGenericPassword
                ] as [CFString: Any] as CFDictionary
                
                _ = SecItemDelete(query)
            }
        }
    }
    
    init(account: String) {
        self.account = account
    }
}
