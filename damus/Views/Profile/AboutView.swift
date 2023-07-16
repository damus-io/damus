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
    let max_about_length = 280
    @State var show_full_about: Bool = false
    @State private var about_string: AttributedString? = nil
    
    var body: some View {
        Group {
            if let about_string {
                let truncated_about = show_full_about ? about_string : about_string.truncateOrNil(maxLength: max_about_length)
                SelectableText(attributedString: truncated_about ?? about_string, size: .subheadline)

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
            let blocks = parse_note_content(content: about, tags: [])
            about_string = render_blocks(blocks: blocks, profiles: state.profiles).content.attributed
        }
        
    }
}

/*
 #Preview {
 AboutView()
 }
 */
