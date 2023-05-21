//
//  TwitterSearchBar.swift
//  damus
//
//  Created by Joel Klabo on 5/15/23.
//

import SwiftUI

struct TwitterSearchBar: View {
    @Binding var searchText: String

    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.gray)
            TextField(NSLocalizedString("Find a Twitter handle's followers on Nostr", comment: "Placeholder for Twitter search bar"), text: $searchText)
                .autocorrectionDisabled()
                .autocapitalization(.none)
                .foregroundColor(.black)
                .font(.callout)
        }
        .padding(8)
        .background(Color.gray.opacity(0.2))
        .cornerRadius(12)
        .padding(.horizontal)
    }
}

struct TwitterSearchBar_Previews: PreviewProvider {
    static var previews: some View {
        TwitterSearchBar(searchText: .constant(""))
    }
}
