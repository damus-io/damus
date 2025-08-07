//
//  LiveStreamViewers.swift
//  damus
//
//  Created by eric on 8/8/25.
//

import SwiftUI

struct LiveStreamViewers: View {
    let state: DamusState
    var currentParticipants: Int
    var preview: Bool
    
    var body: some View {
        HStack(alignment: .center) {
            let viewerCount = currentParticipants
            let nounString = pluralizedString(key: "viewer_count", count: viewerCount)
            let nounText = Text(verbatim: nounString).font(.subheadline).foregroundColor(DamusColors.adaptableWhite)
            
            if preview {
                Text("\(Text(verbatim: viewerCount.formatted()).font(.subheadline.weight(.medium))) \(nounText)", comment: "Sentence composed of 2 variables to describe how many people are viewing the live event. In source English, the first variable is the number of viewers, and the second variable is 'viewer' or 'viewers'.")
                    .foregroundColor(DamusColors.adaptableWhite)
            } else {
                Image("user")
                    .resizable()
                    .frame(width: 15, height: 15)
                Text("\(Text(verbatim: viewerCount.formatted()).font(.subheadline.weight(.medium)))", comment: "number")
            }
        }
        .padding(.vertical, preview ? 2 : 0)
        .padding(.horizontal, preview ? 7 : 0)
        .background(preview ? DamusColors.adaptableBlack.opacity(0.5) : .clear)
        .cornerRadius(preview ? 10 : 0)
    }
}
