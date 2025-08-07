//
//  LiveStreamStatus.swift
//  damus
//
//  Created by eric on 8/8/25.
//

import SwiftUI

struct LiveStreamStatus: View {
    let status: LiveEventStatus
    let starts: String?
    
    var body: some View {
        HStack {
            switch status {
            case .planned:
                Image("calendar")
                    .foregroundColor(Color.white)
                
                if let starts = starts {
                    Text("\(starts)")
                        .foregroundColor(Color.white)
                        .bold()
                        .glow()
                } else {
                    Text("\(status.rawValue)")
                        .foregroundColor(Color.white)
                        .bold()
                }
            case .live:
                Image("record")
                    .foregroundColor(Color.red)
                    .glow()
                
                Text("\(status.rawValue)")
                    .foregroundColor(DamusColors.adaptableWhite)
                    .bold()
            case .ended:
                Text("\(status.rawValue)")
                    .foregroundColor(DamusColors.adaptableWhite)
                    .bold()
            }
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 7)
        .background(DamusColors.adaptableBlack.opacity(0.5))
        .cornerRadius(10)
        .padding(10)
    }
}
