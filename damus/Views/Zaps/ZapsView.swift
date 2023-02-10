//
//  ZapsView.swift
//  damus
//
//  Created by William Casarin on 2023-02-10.
//

import SwiftUI

struct ZapsView: View {
    let state: DamusState
    @StateObject var model: ZapsModel
    
    init(state: DamusState, target: ZapTarget) {
        self.state = state
        self._model = StateObject(wrappedValue: ZapsModel(profiles: state.profiles, pool: state.pool, target: target))
    }
    
    var body: some View {
        ScrollView {
            LazyVStack {
                ForEach(model.zaps, id: \.event.id) { zap in
                    ZapEvent(damus: state, zap: zap)
                        .padding()
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
        ZapsView(state: test_damus_state(), target: .profile("pk"))
    }
}
