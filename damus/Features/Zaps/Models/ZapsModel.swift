//
//  ZapsModel.swift
//  damus
//
//  Created by William Casarin on 2023-02-10.
//

import Foundation

@MainActor
class ZapsModel: ObservableObject {
    let state: DamusState
    let target: ZapTarget
    
    var zapCommsListener: Task<Void, Never>? = nil
    let profiles_subid = UUID().description
    
    init(state: DamusState, target: ZapTarget) {
        self.state = state
        self.target = target
    }
    
    var zaps: [Zapping] {
        return state.events.lookup_zaps(target: target)
    }
    
    func subscribe() {
        var filter = NostrFilter(kinds: [.zap])
        switch target {
        case .profile(let profile_id):
            filter.pubkeys = [profile_id]
        case .note(let note_target):
            filter.referenced_ids = [note_target.note_id]
        }
        zapCommsListener?.cancel()
        zapCommsListener = Task.detached {
            for await event in self.state.nostrNetwork.reader.streamIndefinitely(filters: [filter]) {
                await event.justUseACopy({ await self.handle_event(ev: $0) })
            }
        }
    }
    
    func unsubscribe() {
        zapCommsListener?.cancel()
        zapCommsListener = nil
    }
    
    @MainActor
    func handle_event(ev: NostrEvent) {
        guard ev.kind == 9735,
              let zapper = state.profiles.lookup_zapper(pubkey: target.pubkey),
              let zap = Zap.from_zap_event(zap_ev: ev, zapper: zapper, our_privkey: state.keypair.privkey)
        else {
            return
        }
        
        self.state.add_zap(zap: .zap(zap))
    }
}
