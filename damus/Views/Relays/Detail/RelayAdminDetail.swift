//
//  RelayAdminDetail.swift
//  damus
//
//  Created by eric on 4/1/24.
//

import SwiftUI

struct RelayAdminDetail: View {
    
    let state: DamusState
    let nip11: RelayMetadata?
    
    var body: some View {
        HStack(spacing: 15) {
            VStack(spacing: 10) {
                Text("ADMIN", comment: "Text label indicating the profile picture underneath it is the admin of the Nostr relay.")
                    .font(.caption)
                    .fontWeight(.heavy)
                    .foregroundColor(DamusColors.mediumGrey)
                if let pubkey = nip11?.pubkey {
                    ProfilePicView(pubkey: pubkey, size: 40, highlight: .custom(.gray.opacity(0.5), 1), profiles: state.profiles, disable_animation: state.settings.disable_animation)
                        .padding(.bottom, 5)
                        .onTapGesture {
                            state.nav.push(route: Route.ProfileByKey(pubkey: pubkey))
                        }
                } else {
                    Image("user-circle")
                        .resizable()
                        .frame(width: 50, height: 50)
                        .foregroundColor(.gray.opacity(0.5))
                }
            }
            
            Divider().frame(width: 1)
            
            VStack {
                Text("CONTACT", comment: "Text label indicating that the information below is the contact information of the admin of the Nostr relay.")
                    .font(.caption)
                    .fontWeight(.heavy)
                    .foregroundColor(DamusColors.mediumGrey)
                Image("messages")
                    .foregroundColor(.gray)
                if let contact = nip11?.contact, !contact.isEmpty {
                    Text(contact)
                        .font(.subheadline)
                        .foregroundColor(.gray)
                } else {
                    Text("N/A", comment: "Text label indicating that there is no NIP-11 relay admin contact information found. In English, N/A stands for not applicable.")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
            }
        }
    }
}

struct RelayAdminDetail_Previews: PreviewProvider {
    static var previews: some View {
        let metadata = RelayMetadata(name: "name", description: "Relay description", pubkey: test_pubkey, contact: "contact@mail.com", supported_nips: [1,2,3], software: "software", version: "version", limitation: Limitations.empty, payments_url: "https://jb55.com", icon: "", fees: Fees.empty)
        RelayAdminDetail(state: test_damus_state, nip11: metadata)
    }
}
