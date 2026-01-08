//
//  RelayType.swift
//  damus
//
//  Created by William Casarin on 2023-02-10.
//

import SwiftUI

struct RelayType: View {
    let is_paid: Bool
    var is_profile_only: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            if is_paid {
                Image("bitcoin-logo")
            }
            if is_profile_only {
                Text("Profile")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(DamusColors.purple)
                    .cornerRadius(4)
            }
        }
    }
}

struct RelayType_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            RelayType(is_paid: false)
            RelayType(is_paid: true)
            RelayType(is_paid: false, is_profile_only: true)
            RelayType(is_paid: true, is_profile_only: true)
        }
    }
}
