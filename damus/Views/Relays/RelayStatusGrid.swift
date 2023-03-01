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

    let columns = [
        GridItem(.fixed(0)),
        GridItem(.fixed(0)),
        GridItem(.fixed(0)),
        GridItem(.fixed(0)),
        GridItem(.fixed(0))
    ]
    
    var body: some View {
        LazyVGrid(columns: columns, spacing: 2) {
            ForEach(pool.relays, id: \.id) { relay in
                let relayString = relay.descriptor.url.absoluteString
                RelayStatus(pool: pool, relay: relayString, size: 4)
            }
        }
    }
}

struct RelayStatusGrid_Previews: PreviewProvider {
    static var previews: some View {
        RelayStatusGrid(pool: test_damus_state().pool)
    }
}
