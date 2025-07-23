//
//  HighlightDraftContentView.swift
//  damus
//
//  Created by eric on 5/26/24.
//

import SwiftUI

struct HighlightDraftContentView: View {
    let draft: HighlightContentDraft
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                var attributedString: AttributedString {
                    var attributedString = AttributedString(draft.selected_text)
                    
                    if let range = attributedString.range(of: draft.selected_text) {
                        attributedString[range].backgroundColor = DamusColors.highlight
                    }
                    
                    return attributedString
                }
                
                Text(attributedString)
                    .lineSpacing(5)
                    .padding(10)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 25).fill(DamusColors.highlight).frame(width: 4),
                alignment: .leading
            )
            
            if case .external_url(let url) = draft.source {
                LinkViewRepresentable(meta: .url(url))
                    .frame(height: 50)
                    
            }
        }
    }
}
