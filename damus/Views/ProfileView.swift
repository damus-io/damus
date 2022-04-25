//
//  ProfileView.swift
//  damus
//
//  Created by William Casarin on 2022-04-23.
//

import SwiftUI

struct ProfileView: View {
    let profile: Profile? = nil
    
    var body: some View {
        VStack {
            ProfilePicView(picture: profile?.picture, size: 64, highlight: .custom(Color.black, 4))
            //ProfileName(pubkey: <#T##String#>, profile: <#T##Profile?#>)
        }
        .navigationBarTitle("Profile")
    }
}

struct ProfileView_Previews: PreviewProvider {
    static var previews: some View {
        ProfileView()
    }
}
