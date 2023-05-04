//
//  RepostAction.swift
//  damus
//
//  Created by William Casarin on 2023-04-19.
//

import SwiftUI

struct RepostAction: View {
    let damus_state: DamusState
    let event: NostrEvent
    
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack {
            Text("Repost Note", comment: "Title text to indicate that the buttons below are meant to be used to repost a note to others.")
                .padding()
                .font(.system(size: 17, weight: .bold))
            
            Spacer()

            HStack(alignment: .top, spacing: 100) {
                
                ShareActionButton(img: "arrow.2.squarepath", text: NSLocalizedString("Repost", comment: "Button to repost a note")) {
                    dismiss()
                                
                    guard let privkey = self.damus_state.keypair.privkey else {
                        return
                    }
                    
                    let boost = make_boost_event(pubkey: damus_state.keypair.pubkey, privkey: privkey, boosted: self.event)
                    
                    damus_state.postbox.send(boost)
                }
                
                ShareActionButton(img: "quote.opening", text: NSLocalizedString("Quote", comment: "Button to compose a quoted note")) {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        notify(.compose, PostAction.quoting(self.event))
                    }
                }
                
            }
            
            Spacer()
            
            HStack {
                BigButton(NSLocalizedString("Cancel", comment: "Button to cancel a repost.")) {
                    dismiss()
                }
            }
        }
    }
}

struct RepostAction_Previews: PreviewProvider {
    static var previews: some View {
        RepostAction(damus_state: test_damus_state(), event: test_event)
    }
}
