//
//  ReplyView.swift
//  damus
//
//  Created by William Casarin on 2022-04-17.
//

import SwiftUI

struct ReplyView: View {
    let replying_to: NostrEvent
    
    var body: some View {
        VStack {
            Text("Replying to:")
            EventView(event: replying_to, highlight: .none, has_action_bar: false)
            PostView(references: replying_to.reply_ids(pubkey: replying_to.pubkey))
            
            Spacer()
        }
        .padding()
        
    }
    
    
}

/*
struct ReplyView_Previews: PreviewProvider {
    static var previews: some View {
        ReplyView()
    }
}
 */
