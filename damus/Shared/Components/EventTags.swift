//
//  EventTags.swift
//  damus
//
//  Created by eric on 8/8/25.
//

import SwiftUI

struct EventTags: View {
    var tags: [String]?
    
    var body: some View {
        ScrollView(.horizontal) {
            HStack {
                ForEach(tags ?? [], id: \.self) { tag in
                    Text(tag)
                        .font(.caption2)
                        .foregroundColor(.gray)
                        .padding(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
                        .background(DamusColors.neutral1)
                        .cornerRadius(20)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(DamusColors.neutral3, lineWidth: 1)
                        )
                }
            }.padding(.horizontal, 5)
        }
        .padding(.bottom, 5)
        .scrollIndicators(.hidden)
    }
}
