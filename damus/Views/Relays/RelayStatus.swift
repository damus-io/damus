//
//  RelayStatus.swift
//  damus
//
//  Created by William Casarin on 2023-02-10.
//

import SwiftUI

extension RelayConnection.State {
    var indicatorColor: Color {
        switch self {
        case .connected: return .green
        case .connecting, .reconnecting: return .yellow
        default: return .red
        }
    }
}

struct RelayStatus: View {
    let pool: RelayPool
    let relay: String
    
    let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()
    
    @State var conn_color: Color = .gray
    
    func update_connection_color() {
        guard let relay = pool.relays.first(where: { $0.id == relay }) else {
            return
        }
        conn_color = relay.connection.state.indicatorColor
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
