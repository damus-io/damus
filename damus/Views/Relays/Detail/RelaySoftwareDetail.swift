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
                Text("SOFTWARE")
                    .font(.caption)
                    .fontWeight(.heavy)
                    .foregroundColor(DamusColors.mediumGrey)
                
                Image("code")
                    .foregroundColor(.gray)
                
                let software = nip11?.software
                let softwareSeparated = software?.components(separatedBy: "/")
                let softwareShortened = softwareSeparated?.last
                Text(softwareShortened ?? "N/A")
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
            
            Divider().frame(width: 1)
            
            VStack {
                Text("VERSION")
                    .font(.caption)
                    .fontWeight(.heavy)
                    .foregroundColor(DamusColors.mediumGrey)
                
                Image("branches")
                    .foregroundColor(.gray)
                
                Text(nip11?.version ?? "N/A")
                    .font(.subheadline)
                    .foregroundColor(.gray)
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
