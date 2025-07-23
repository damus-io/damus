//
//  ZapType.swift
//  damus
//
//  Created by Daniel D’Aquino on 2023-11-24.
//

import Foundation

enum ZapType: String, StringCodable {
    case pub
    case anon
    case priv
    case non_zap
    
    init?(from string: String) {
        guard let v = ZapType(rawValue: string) else {
            return nil
        }
        
        self = v
    }
    
    func to_string() -> String {
        return self.rawValue
    }
    
}
