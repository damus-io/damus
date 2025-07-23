//
//  UserStatus.swift
//  damus
//
//  Created by William Casarin on 2023-08-21.
//

import SwiftUI
import MediaPlayer
import WebKit

struct UserStatusView: View {
    @ObservedObject var status: UserStatusModel

    var show_general: Bool
    var show_music: Bool

    @Environment(\.openURL) var openURL

    func Status(st: UserStatus, prefix: String = "") -> some View {
        HStack {
            Text(verbatim: "\(prefix)\(st.content)")
                .lineLimit(1)
                .foregroundColor(.gray)
                .font(.callout.italic())
            if st.url != nil {
                Image("link")
                    .resizable()
                    .frame(width: 16, height: 16)
                    .foregroundColor(.gray)
            }
        }
        .onTapGesture {
            if let url = st.url {
                openURL(url)
            }
        }
        .contextMenu(
            menuItems: {
                if let url = st.url {
                    Button(url.absoluteString, action: { openURL(url) }) }
            }, preview: {
                if let url = st.url {
                    URLPreview(url: url)
                }
            })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if show_general, let general = status.general {
                Status(st: general)
            }

            if show_music, let playing = status.music {
                Status(st: playing, prefix: "🎵")
            }
        }

    }

    struct URLPreview: UIViewRepresentable {
        var url: URL

        func makeUIView(context: Context) -> WKWebView {
            return WKWebView()
        }

        func updateUIView(_ wkView: WKWebView, context: Context) {
            let request = URLRequest(url: url)
            wkView.load(request)
        }
    }
}

/*
struct UserStatusView_Previews: PreviewProvider {
    static var previews: some View {
        UserStatusView(status: UserStatus(type: .music, expires_at: nil, content: "Track - Artist", created_at: 0, url: URL(string: "spotify:search:abc")), show_general: true, show_music: true)
    }
}

*/
