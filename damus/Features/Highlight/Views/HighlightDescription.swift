//
//  HighlightDescription.swift
//  damus
//
//  Created by eric on 4/28/24.
//

import SwiftUI

// Modified from Reply Description
struct HighlightDescription: View {
    let highlight_event: HighlightEvent
    let highlighted_event: NostrEvent?
    let ndb: Ndb

    var body: some View {
        (Text(Image(systemName: "highlighter")) + Text(verbatim: " \(highlight_event.source_description_text(ndb: ndb, highlighted_event: highlighted_event))"))
            .font(.footnote)
            .foregroundColor(DamusColors.mediumGrey)
            .frame(maxWidth: .infinity, alignment: .leading)

    }
}

struct HighlightDescription_Previews: PreviewProvider {
    static var previews: some View {
        HighlightDescription(highlight_event: HighlightEvent.parse(from: test_note), highlighted_event: nil, ndb: test_damus_state.ndb)
    }
}
