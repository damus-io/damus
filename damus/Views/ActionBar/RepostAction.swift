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
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(alignment: .leading) {
            
            Button {
                dismiss()
                            
                guard let privkey = self.damus_state.keypair.privkey else {
                    return
                }
                
                let boost = make_boost_event(pubkey: damus_state.keypair.pubkey, privkey: privkey, boosted: self.event)
                
                damus_state.postbox.send(boost)
            } label: {
                Label(NSLocalizedString("Repost", comment: "Button to repost a note"), systemImage: "arrow.2.squarepath")
                    .frame(maxWidth: .infinity, minHeight: 50, maxHeight: 50, alignment: .leading)

            }
            .font(.system(size: 20, weight: .regular))
            .foregroundColor(colorScheme == .light ? Color("DamusBlack") : Color("DamusWhite"))
            .padding(EdgeInsets(top: 25, leading: 50, bottom: 0, trailing: 50))
            
            Button {
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    notify(.compose, PostAction.quoting(self.event))
                }
                
            } label: {
                Label(NSLocalizedString("Quote", comment: "Button to compose a quoted note"), systemImage: "quote.opening")
                    .frame(maxWidth: .infinity, minHeight: 50, maxHeight: 50, alignment: .leading)

            }
            .font(.system(size: 20, weight: .regular))
            .foregroundColor(colorScheme == .light ? Color("DamusBlack") : Color("DamusWhite"))
            .padding(EdgeInsets(top: 0, leading: 50, bottom: 0, trailing: 50))
            
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
