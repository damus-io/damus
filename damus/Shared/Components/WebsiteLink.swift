//
//  WebsiteLink.swift
//  damus
//
//  Created by William Casarin on 2023-01-22.
//

import SwiftUI

struct WebsiteLink: View {
    let url: URL
    let style: StyleVariant
    @Environment(\.openURL) var openURL
    
    init(url: URL, style: StyleVariant? = nil) {
        self.url = url
        self.style = style ?? .normal
    }

    var body: some View {
        Button(action: {
            openURL(url)
        }) {
            HStack {
                Image("link")
                    .resizable()
                    .frame(width: 16, height: 16)
                    .foregroundColor(self.style == .accent ? .white : .gray)
                    .padding([.leading], 10)

                Text(link_text)
                    .font(.footnote)
                    .foregroundColor(self.style == .accent ? .white : .accentColor)
                    .truncationMode(.tail)
                    .lineLimit(1)
                    .padding([.trailing], 10)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .background(
            self.style == .accent ?
                AnyView(RoundedRectangle(cornerRadius: 50).fill(PinkGradient))
              : AnyView(Color.clear)
        )
    }
    
    var link_text: String {
        url.host ?? url.absoluteString
    }
    
    enum StyleVariant {
        case normal
        case accent
    }
}

struct WebsiteLink_Previews: PreviewProvider {
    static var previews: some View {
        WebsiteLink(url: URL(string: "https://jb55.com")!)
            .previewDisplayName("Normal")
        WebsiteLink(url: URL(string: "https://jb55.com")!, style: .accent)
            .previewDisplayName("Accent")
    }
}
