//
//  RelayStatusGrid.swift
//  damus
//
//  Created by Honk on 2/28/23.
//

import SwiftUI

struct RelayStatusGrid: View {
    let pool: RelayPool
    
    let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()
    
    let maxColumns = 4
    let columns = [
        GridItem(.adaptive(minimum: 8, maximum: 16), spacing: 8),
        GridItem(.adaptive(minimum: 8, maximum: 16), spacing: 8),
        GridItem(.adaptive(minimum: 8, maximum: 16), spacing: 8),
        GridItem(.adaptive(minimum: 8, maximum: 16), spacing: 8)
    ]
    
    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(pool.relays, id: \.id) { relay in
                let relayString = relay.descriptor.url.absoluteString
                RelayStatus(pool: pool, relay: relayString)
            }
        }
    }
}

struct RelayStatusGrid_Previews: PreviewProvider {
    static var previews: some View {
        RelayStatusGrid(pool: test_damus_state().pool)
    }
}
