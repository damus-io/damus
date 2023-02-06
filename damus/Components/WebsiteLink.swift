//
//  WebsiteLink.swift
//  damus
//
//  Created by William Casarin on 2023-01-22.
//

import SwiftUI

struct WebsiteLink: View {
    let url: URL
    @Environment(\.openURL) var openURL

    var body: some View {
        HStack {
            Image(systemName: "link")
                .foregroundColor(.gray)
                .font(.footnote)
            
            Button(action: {
                openURL(url)
            }, label: {
                Text(link_text)
                    .font(.footnote)
            })
        }
    }
    
    var link_text: String {
        url.host ?? url.absoluteString
    }
}

struct WebsiteLink_Previews: PreviewProvider {
    static var previews: some View {
        WebsiteLink(url: URL(string: "https://jb55.com")!)
    }
}
