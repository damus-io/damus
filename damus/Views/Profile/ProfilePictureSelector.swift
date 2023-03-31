//
//  ProfilePictureSelector.swift
//  damus
//
//  Created by William Casarin on 2022-05-20.
//

import SwiftUI

struct ProfilePictureSelector: View {

    @StateObject var account: CreateAccountModel
    @State var is_editing = true

    @State private var show_camera = false
    @State private var show_library = false
    
    
    var body: some View {
        let highlight: Highlight = .custom(Color.white, 2.0)
        ZStack {
            ProfilePicView(pubkey: account.pubkey, size: 80.0, highlight: highlight, profiles: Profiles())
                .opacity(is_editing ? 0.5 : 1)
            if is_editing {
                ProfilePictureEditView(account: account)
            }
        }
    }
}

//struct ProfilePictureSelector_Previews: PreviewProvider {
//    static var previews: some View {
//        let test_pubkey = "ff48854ac6555fed8e439ebb4fa2d928410e0eef13fa41164ec45aaaa132d846"
//        ProfilePictureSelector(pubkey: test_pubkey)
//    }
//}
