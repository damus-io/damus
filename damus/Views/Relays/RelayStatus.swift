//
//  RelayStatus.swift
//  damus
//
//  Created by William Casarin on 2023-02-10.
//

import SwiftUI

struct RelayStatus: View {
    let pool: RelayPool
    let relay: String
    
    let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()
    
    @State var conn_color: Color = .gray
    
    func update_connection_color() {
        for relay in pool.relays {
            if relay.id == self.relay {
                let c = relay.connection
                if c.isConnected {
                    conn_color = .green
                } else if c.isConnecting || c.isReconnecting {
                    conn_color = .yellow
                } else {
                    conn_color = .red
                }
            }
        }
    }
    
    var body: some View {
        Circle()
            .frame(width: 8.0, height: 8.0)
            .foregroundColor(conn_color)
            .onReceive(timer) { _ in
                update_connection_color()
            }
            .onAppear() {
                update_connection_color()
            }
    }
}

struct RelayStatus_Previews: PreviewProvider {
    static var previews: some View {
        RelayStatus(pool: test_damus_state().pool, relay: "relay")
    }
}
