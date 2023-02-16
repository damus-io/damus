//
//  RelayPaidDetail.swift
//  damus
//
//  Created by William Casarin on 2023-02-10.
//

import SwiftUI

struct RelayPaidDetail: View {
    let payments_url: String?
    
    @Environment(\.openURL) var openURL
    
    var body: some View {
        HStack {
            RelayType(is_paid: true)
            if let url = payments_url.flatMap({ URL(string: $0) }) {
                Button(action: {
                    openURL(url)
                }, label: {
                    Text(String("\(url)"))
                })
            }
        }
    }
}

struct RelayPaidDetail_Previews: PreviewProvider {
    static var previews: some View {
        RelayPaidDetail(payments_url: "https://jb55.com")
    }
}
