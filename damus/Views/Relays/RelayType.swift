//
//  RelayType.swift
//  damus
//
//  Created by William Casarin on 2023-02-10.
//

import SwiftUI

struct RelayType: View {
    let is_paid: Bool
    
    var body: some View {

        Image(systemName: is_paid ? "dollarsign.circle.fill" : "globe.americas.fill")
            .foregroundColor(is_paid ? Color("DamusGreen") : .gray)
    }
}

struct RelayType_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            RelayType(is_paid: false)
            RelayType(is_paid: true)
        }
    }
}
