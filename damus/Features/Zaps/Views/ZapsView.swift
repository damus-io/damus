//
//  ZapsView.swift
//  damus
//
//  Created by William Casarin on 2023-02-10.
//

import SwiftUI

struct ZapsView: View {
    let state: DamusState
    var model: ZapsModel
    
    @ObservedObject var zaps: ZapsDataModel
    
    init(state: DamusState, target: ZapTarget) {
        self.state = state
        self.model = ZapsModel(state: state, target: target)
        self._zaps = ObservedObject(wrappedValue: state.events.get_cache_data(NoteId(target.id)).zaps_model)
    }
    
    var body: some View {
        ScrollView {
            LazyVStack {
                ForEach(zaps.zaps, id: \.request.ev.id) { zap in
                    ZapEvent(damus: state, zap: zap, is_top_zap: false)
                        .padding([.horizontal])
                }
            }
        }
        .navigationBarTitle(NSLocalizedString("Zaps", comment: "Navigation bar title for the Zaps view."))
        .onAppear {
            model.subscribe()
        }
        .onDisappear {
            model.unsubscribe()
        }
    }
}

struct ZapsView_Previews: PreviewProvider {
    static var previews: some View {
        ZapsView(state: test_damus_state, target: .profile(test_pubkey))
    }
}
