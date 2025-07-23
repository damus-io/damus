//
//  ZapDataModel.swift
//  damus
//
//  Created by Daniel D’Aquino on 2023-11-27.
//

import Foundation

class ZapsDataModel: ObservableObject {
    @Published var zaps: [Zapping]
    
    init(_ zaps: [Zapping]) {
        self.zaps = zaps
    }
    
    func confirm_nwc(reqid: NoteId) {
        guard let zap = zaps.first(where: { z in z.request.ev.id == reqid }),
              case .pending(let pzap) = zap
        else {
            return
        }
        
        switch pzap.state {
        case .external:
            break
        case .nwc(let nwc_state):
            if nwc_state.update_state(state: .confirmed) {
                self.objectWillChange.send()
            }
        }
    }
    
    var zap_total: Int64 {
        zaps.reduce(0) { total, zap in total + zap.amount }
    }
   
    func from(_ pubkey: Pubkey) -> [Zapping] {
        return self.zaps.filter { z in z.request.ev.pubkey == pubkey }
    }
    
    @discardableResult
    func remove(reqid: ZapRequestId) -> Bool {
        guard zaps.first(where: { z in z.request.id == reqid }) != nil else {
            return false
        }
        
        self.zaps = zaps.filter { z in z.request.id != reqid }
        return true
    }
}
