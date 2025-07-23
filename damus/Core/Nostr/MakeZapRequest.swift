//
//  MakeZapRequest.swift
//  damus
//
//  Created by Daniel D’Aquino on 2023-11-27.
//

import Foundation

enum MakeZapRequest {
    case priv(ZapRequest, PrivateZapRequest)
    case normal(ZapRequest)
    
    var private_inner_request: ZapRequest {
        switch self {
        case .priv(_, let pzr):
            return pzr.req
        case .normal(let zr):
            return zr
        }
    }
    
    var potentially_anon_outer_request: ZapRequest {
        switch self {
        case .priv(let zr, _):
            return zr
        case .normal(let zr):
            return zr
        }
    }
}

struct PrivateZapRequest {
    let req: ZapRequest
    let enc: String
}
