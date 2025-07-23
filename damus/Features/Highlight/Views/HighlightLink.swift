//
//  HighlightLink.swift
//  damus
//
//  Created by eric on 4/28/24.
//

import SwiftUI
import Kingfisher

struct HighlightLink: View {
    let state: DamusState
    let url: URL
    let content: String
    @Environment(\.openURL) var openURL

    func text_fragment_url() -> URL? {
        let fragmentDirective = "#:~:"
        let textDirective = "text="
        let separator = ","
        var text = ""

        let components = content.components(separatedBy: " ")
        if components.count <= 10 {
            text = content
        } else {
            let textStart = Array(components.prefix(5)).joined(separator: " ")
            let textEnd = Array(components.suffix(2)).joined(separator: " ")
            text = textStart + separator + textEnd
        }

        let url_with_fragments = url.absoluteString + fragmentDirective + textDirective + text
        return URL(string: url_with_fragments)
    }

    func get_url_icon() -> URL? {
        var icon = URL(string: url.absoluteString + "/favicon.ico")
        if let url_host = url.host() {
            icon = URL(string: "https://" + url_host + "/favicon.ico")
        }
        return icon
    }

    var body: some View {
        Button(action: {
            openURL(text_fragment_url() ?? url)
        }, label: {
            HStack(spacing: 10) {
                if let url = get_url_icon() {
                    KFAnimatedImage(url)
                        .imageContext(.pfp, disable_animation: true)
                        .cancelOnDisappear(true)
                        .configure { view in
                            view.framePreloadCount = 3
                        }
                        .placeholder { _ in
                            Image("link")
                                .resizable()
                                .padding(5)
                                .foregroundColor(DamusColors.neutral6)
                                .background(DamusColors.adaptableWhite)
                        }
                        .frame(width: 35, height: 35)
                        .kfClickable()
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .scaledToFit()
                } else {
                    Image("link")
                        .resizable()
                        .padding(5)
                        .foregroundColor(DamusColors.neutral6)
                        .background(DamusColors.adaptableWhite)
                        .frame(width: 35, height: 35)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                Text(url.absoluteString)
                    .font(eventviewsize_to_font(.normal, font_size: state.settings.font_size))
                    .foregroundColor(DamusColors.adaptableBlack)
                    .truncationMode(.tail)
                    .lineLimit(1)
            }
            .padding([.leading, .vertical], 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DamusColors.neutral3)
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(DamusColors.neutral3, lineWidth: 2)
            )
        })
    }
}

struct HighlightLink_Previews: PreviewProvider {
    static var previews: some View {
        let url = URL(string: "https://damus.io")!
        VStack {
            HighlightLink(state: test_damus_state, url: url, content: "")
        }
    }
}
