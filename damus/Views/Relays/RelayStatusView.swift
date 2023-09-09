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
                Text("Connecting")
                    .font(.caption)
                    .frame(height: 20)
                    .padding(.horizontal, 10)
                    .foregroundColor(DamusColors.warning)
                    .background(DamusColors.warningQuaternary)
                    .cornerRadius(20)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(DamusColors.warningBorder, lineWidth: 1)
                    )
            } else if connection.isConnected {
                Text("Online")
                    .font(.caption)
                    .frame(height: 20)
                    .padding(.horizontal, 10)
                    .foregroundColor(DamusColors.success)
                    .background(DamusColors.successQuaternary)
                    .cornerRadius(20)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(DamusColors.successBorder, lineWidth: 1)
                    )
            } else {
                Text("Error")
                    .font(.caption)
                    .frame(height: 20)
                    .padding(.horizontal, 10)
                    .foregroundColor(DamusColors.danger)
                    .background(DamusColors.dangerQuaternary)
                    .border(DamusColors.dangerBorder)
                    .cornerRadius(20)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(DamusColors.dangerBorder, lineWidth: 1)
                    )
            }
        }
        .padding(.trailing, 20)
    }
}

struct RelayStatusView_Previews: PreviewProvider {
    static var previews: some View {
        let connection = test_damus_state().pool.get_relay("wss://relay.damus.io")!.connection
        RelayStatusView(connection: connection)
    }
}
