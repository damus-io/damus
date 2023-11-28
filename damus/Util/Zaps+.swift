//
//  Zaps+.swift
//  damus
//
//  Created by Daniel D’Aquino on 2023-11-27.
//

import Foundation

func remove_zap(reqid: ZapRequestId, zapcache: Zaps, evcache: EventCache) {
    guard let zap = zapcache.remove_zap(reqid: reqid.reqid) else {
        return
    }
    evcache.get_cache_data(NoteId(zap.target.id)).zaps_model.remove(reqid: reqid)
}
