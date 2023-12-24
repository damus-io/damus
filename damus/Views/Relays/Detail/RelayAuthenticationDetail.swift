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
            Text(NSLocalizedString("Pending", comment: "Label to display that authentication to a server is pending."))
        case .verified:
            Text(NSLocalizedString("Authenticated", comment: "Label to display that authentication to a server has succeeded."))
                .foregroundStyle(DamusColors.success)
        case .error:
            Text(NSLocalizedString("Error", comment: "Label to display that authentication to a server has failed."))
                .foregroundStyle(DamusColors.danger)
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
