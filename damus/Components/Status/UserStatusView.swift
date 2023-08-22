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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let general = status.general {
                Text(verbatim: "\(general.content)")
                    .foregroundColor(.gray)
                    .font(.callout.italic())
            }

            if let playing = status.music {
                Text(verbatim: "🎵\(playing.content)")
                    .foregroundColor(.gray)
                    .font(.callout.italic())
            }
        }

    }
}

struct UserStatusView_Previews: PreviewProvider {
    static var previews: some View {
        UserStatusView(status: .init())
    }
}
