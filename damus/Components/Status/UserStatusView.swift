//
//  UserStatus.swift
//  damus
//
//  Created by William Casarin on 2023-08-21.
//

import SwiftUI
import MediaPlayer


struct UserStatusView: View {
    @ObservedObject var status: UserStatusModel

    var show_general: Bool
    var show_music: Bool

    @Environment(\.openURL) var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if show_general, let general = status.general {
                Text(verbatim: "\(general.content)")
                    .lineLimit(1)
                    .foregroundColor(.gray)
                    .font(.callout.italic())
                    .onTapGesture {
                        if let url = general.url {
                            openURL(url)
                        }
                    }
            }

            if show_music, let playing = status.music {
                Text(verbatim: "🎵\(playing.content)")
                    .lineLimit(1)
                    .foregroundColor(.gray)
                    .font(.callout.italic())
                    .onTapGesture {
                        if let url = playing.url {
                            openURL(url)
                        }
                    }
            }
        }

    }
}

struct UserStatusView_Previews: PreviewProvider {
    static var previews: some View {
        UserStatusView(status: .init(), show_general: true, show_music: true)
    }
}
