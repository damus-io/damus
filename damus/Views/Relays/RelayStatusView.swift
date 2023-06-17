//
//  RelayStatusView.swift
//  damus
//
//  Created by William Casarin on 2023-02-10.
//

import SwiftUI

struct RelayStatusView: View {
    @ObservedObject var connection: RelayConnection
    
    var body: some View {
        Group {
            if connection.isConnecting {
                ProgressView()
            } else {
                Image(connection.isConnected ? "globe" : "warning.fill")
                    .resizable()
                    .foregroundColor(connection.isConnected ? .green : .red)
            }
        }
        .frame(width: 20, height: 20)
        .padding(.trailing, 5)
    }
}

struct RelayStatusView_Previews: PreviewProvider {
    static var previews: some View {
        let connection = test_damus_state().pool.get_relay("relay")!.connection
        RelayStatusView(connection: connection)
    }
}
