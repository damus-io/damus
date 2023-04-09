//
//  EmptyUserSearchView.swift
//  damus
//
//  Created by eric on 4/3/23.
//

//
//  EmptyUserSearchView.swift
//  damus
//
//  Created by eric on 4/3/23.
//

import SwiftUI

struct EmptyUserSearchView: View {
    var body: some View {
        VStack {
            Image(systemName: "person.fill.questionmark")
                .font(.system(size: 35))
                .padding()
            Text("Could not find the user you're looking for", comment: "Indicates that there are no users found.")
                .multilineTextAlignment(.center)
                .font(.callout.weight(.medium))
        }
        .foregroundColor(.gray)
        .padding()
    }
}

struct EmptyUserSearchView_Previews: PreviewProvider {
    static var previews: some View {
        EmptyUserSearchView()
    }
}

