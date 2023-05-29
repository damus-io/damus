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
                    conn_image = "globe"
                    conn_color = .green
                } else if c.isConnecting {
                    connecting = true
                } else {
                    conn_image = "warning.fill"
                    conn_color = .red
                }
            }
        }
    }
    
    var body: some View {
        HStack {
            if connecting {
                ProgressView()
                    .frame(width: 20, height: 20)
                    .padding(.trailing, 5)
            } else {
                Image(conn_image)
                    .resizable()
                    .frame(width: 20, height: 20)
                    .foregroundColor(conn_color)
                    .padding(.trailing, 5)
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
