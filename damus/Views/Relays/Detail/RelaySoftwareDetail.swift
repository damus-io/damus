//
//  RelaySoftwareDetail.swift
//  damus
//
//  Created by eric on 4/1/24.
//

import SwiftUI

struct RelaySoftwareDetail: View {
    
    let nip11: RelayMetadata?
    
    var body: some View {
        HStack(spacing: 15) {
            VStack {
                Text("SOFTWARE", comment: "Text label indicating which relay software is used to run this Nostr relay.")
                    .font(.caption)
                    .fontWeight(.heavy)
                    .foregroundColor(DamusColors.mediumGrey)
                
                Image("code")
                    .foregroundColor(.gray)
                
                let software = nip11?.software
                let softwareSeparated = software?.components(separatedBy: "/")
                if let softwareShortened = softwareSeparated?.last {
                    Text(softwareShortened)
                        .font(.subheadline)
                        .foregroundColor(.gray)
                } else {
                    Text("N/A", comment: "Text label indicating that there is no NIP-11 relay software information found. In English, N/A stands for not applicable.")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
            }
            
            Divider().frame(width: 1)
            
            VStack {
                Text("VERSION", comment: "Text label indicating which version of the relay software is being run for this Nostr relay.")
                    .font(.caption)
                    .fontWeight(.heavy)
                    .foregroundColor(DamusColors.mediumGrey)
                
                Image("branches")
                    .foregroundColor(.gray)

                if let version = nip11?.version, !version.isEmpty {
                    Text(version)
                        .font(.subheadline)
                        .foregroundColor(.gray)
                } else {
                    Text("N/A", comment: "Text label indicating that there is no NIP-11 relay software version information found. In English, N/A stands for not applicable.")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
            }
        }
    }
}

struct RelaySoftwareDetail_Previews: PreviewProvider {
    static var previews: some View {
        let metadata = RelayMetadata(name: "name", description: "desc", pubkey: test_pubkey, contact: "contact", supported_nips: [1,2,3], software: "git+https://github.com/hoytech/strfry.git", version: "0.9.6-26-gc0dec7c", limitation: Limitations.empty, payments_url: "https://jb55.com", icon: "", fees: Fees.empty)
        RelaySoftwareDetail(nip11: metadata)
    }
}
