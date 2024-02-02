//
//  AboutView.swift
//  damus
//
//  Created by William Casarin on 2023-06-18.
//

import SwiftUI

struct AboutView: View {
    let state: DamusState
    let about: String
    let max_about_length: Int
    let text_alignment: NSTextAlignment
    @State var show_full_about: Bool = false
    @State private var about_string: AttributedString? = nil
    
    init(state: DamusState, about: String, max_about_length: Int? = nil, text_alignment: NSTextAlignment? = nil) {
        self.state = state
        self.about = about
        self.max_about_length = max_about_length ?? 280
        self.text_alignment = text_alignment ?? .natural
    }
    
    var body: some View {
        Group {
            if let about_string {
                let truncated_about = show_full_about ? about_string : about_string.truncateOrNil(maxLength: max_about_length)
                SelectableText(damus_state: state, event: nil, attributedString: truncated_about ?? about_string, textAlignment: self.text_alignment, size: .subheadline)

                if truncated_about != nil {
                    if show_full_about {
                        Button(NSLocalizedString("Show less", comment: "Button to show less of a long profile description.")) {
                            show_full_about = false
                        }
                        .font(.footnote)
                    } else {
                        Button(NSLocalizedString("Show more", comment: "Button to show more of a long profile description.")) {
                            show_full_about = true
                        }
                        .font(.footnote)
                    }
                }
            } else {
                Text(verbatim: "")
                    .font(.subheadline)
            }
        }
        .onAppear {
            // TODO: Fix about content
            //let blocks = ndb_parse_content(content: .content(about, nil))
            //about_string = render_blocks(blocks: blocks, profiles: state.profiles).content.attributed
        }
        
    }
}

/*
 #Preview {
 AboutView()
 }
 */
