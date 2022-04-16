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
                ProfilePicView(picture: profile?.picture, size: 64)

                Spacer()
            }

            VStack {
                HStack {
                    Text(String(profile?.name ?? String(event.pubkey.prefix(16))))
                        .bold()
                        .onTapGesture {
                            UIPasteboard.general.string = event.pubkey
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Spacer()
                    if (event.pow ?? 0) >= 10 {
                        Text("\(event.pow ?? 0)")
                            .font(.callout)
                            .foregroundColor(calculate_pow_color(event.pow ?? 0))
                    }
                }
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


// TODO: make this less saturated on white theme
func calculate_pow_color(_ pow: Int) -> Color
{
    let x = Double(pow) / 30.0;
    return Color(.sRGB, red: 2.0 * (1.0 - x), green: 2.0 * x, blue: 0, opacity: 0.5)
}
