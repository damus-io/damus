//
//  EventView.swift
//  damus
//
//  Created by William Casarin on 2022-04-11.
//

import Foundation
import SwiftUI
import CachedAsyncImage

struct EventView: View {
    let event: NostrEvent
    let profile: Profile?

    var body: some View {
        HStack {
            VStack {
                if let pic = profile?.picture.flatMap { URL(string: $0) } {
                    CachedAsyncImage(url: pic) { img in
                        img.resizable()
                    } placeholder: {
                        Color.purple.opacity(0.1)
                    }
                    .frame(width: PFP_SIZE, height: PFP_SIZE)
                    .cornerRadius(CORNER_RADIUS)
                } else {
                    Color.purple.opacity(0.1)
                        .frame(width: PFP_SIZE, height: PFP_SIZE)
                        .cornerRadius(CORNER_RADIUS)
                }

                Spacer()
            }

            VStack {
                Text(String(profile?.name ?? String(event.pubkey.prefix(16))))
                    .bold()
                    .onTapGesture {
                        UIPasteboard.general.string = event.pubkey
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(event.content)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Spacer()

                Divider()
            }
        }
        .frame(minHeight: PFP_SIZE)
    }
}

