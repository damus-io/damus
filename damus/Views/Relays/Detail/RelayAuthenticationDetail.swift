//
//  RelayAuthenticationDetail.swift
//  damus
//
//  Created by Charlie Fish on 12/18/23.
//

import SwiftUI

struct RelayAuthenticationDetail: View {
    let state: RelayAuthenticationState

    var body: some View {
        switch state {
        case .none:
            EmptyView()
        case .pending:
            Text("Pending", comment: "Label to display that authentication to a server is pending.")
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
        case .verified:
            Text("Authenticated", comment: "Label to display that authentication to a server has succeeded.")
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
        case .error:
            Text("Error", comment: "Label to display that authentication to a server has failed.")
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
}

struct RelayAuthenticationDetail_Previews: PreviewProvider {
    static var previews: some View {
        RelayAuthenticationDetail(state: .none)
        RelayAuthenticationDetail(state: .pending)
        RelayAuthenticationDetail(state: .verified)
    }
}
