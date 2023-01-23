//
//  ReplyDescription.swift
//  damus
//
//  Created by William Casarin on 2023-01-23.
//

import SwiftUI

// jb55 - TODO: this could be a lot better
struct ReplyDescription: View {
    let event: NostrEvent
    let profiles: Profiles
    
    var body: some View {
        Text("\(reply_desc(profiles: profiles, event: event))")
            .font(.footnote)
            .foregroundColor(.gray)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ReplyDescription_Previews: PreviewProvider {
    static var previews: some View {
        ReplyDescription(event: test_event, profiles: test_damus_state().profiles)
    }
}
