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
    @State var conn_image: String = "network"
    @State var connecting: Bool = false
    
    func update_connection() {
        for relay in pool.relays {
            if relay.id == self.relay {
                let c = relay.connection
                if c.isConnected {
                    conn_image = "network"
                    conn_color = .green
                } else if c.isConnecting || c.isReconnecting {
                    connecting = true
                } else {
                    conn_image = "exclamationmark.circle.fill"
                    conn_color = .red
                }
            }
        }
    }
    
    var body: some View {
        HStack {
            if connecting {
                ProgressView()
                    .padding(.trailing, 4)
            } else {
                Image(systemName: conn_image)
                    .frame(width: 8.0, height: 8.0)
                    .foregroundColor(conn_color)
                    .padding(.leading, 5)
                    .padding(.trailing, 10)
            }
        }
        .onReceive(timer) { _ in
            update_connection()
        }
        .onAppear() {
            update_connection()
        }
        
    }
}

struct RelayStatus_Previews: PreviewProvider {
    static var previews: some View {
        RelayStatus(pool: test_damus_state().pool, relay: "relay")
    }
}
