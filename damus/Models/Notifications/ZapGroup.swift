//
//  ZapGroup.swift
//  damus
//
//  Created by William Casarin on 2023-02-21.
//

import Foundation

class ZapGroup {
    var zaps: [Zap]
    var msat_total: Int64
    var zappers: Set<String>
    
    var last_event_at: Int64 {
        guard let first = zaps.first else {
            return 0
        }
        
        return first.event.created_at
    }
    
    func zap_requests() -> [NostrEvent] {
        zaps.map { z in
            if let priv = z.private_request {
                return priv
            } else {
                return z.request.ev
            }
        }
    }
    
    func would_filter(_ isIncluded: (NostrEvent) -> Bool) -> Bool {
        for zap in zaps {
            if !isIncluded(zap.request_ev) {
                return true
            }
        }
        
        return false
    }
    
    func filter(_ isIncluded: (NostrEvent) -> Bool) -> ZapGroup? {
        let new_zaps = zaps.filter { isIncluded($0.request_ev) }
        guard new_zaps.count > 0 else {
            return nil
        }
        let grp = ZapGroup()
        for zap in new_zaps {
            grp.insert(zap)
        }
        return grp
    }
    
    init() {
        self.zaps = []
        self.msat_total = 0
        self.zappers = Set()
    }
    
    @discardableResult
    func insert(_ zap: Zap) -> Bool {
        if !insert_uniq_sorted_zap_by_created(zaps: &zaps, new_zap: zap) {
            return false
        }
        
        msat_total += zap.invoice.amount
        
        if !zappers.contains(zap.request.ev.pubkey)  {
            zappers.insert(zap.request.ev.pubkey)
        }
        
        return true
    }
}

