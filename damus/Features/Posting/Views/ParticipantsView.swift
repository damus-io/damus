//
//  ParticipantsView.swift
//  damus
//
//  Created by Joel Klabo on 1/18/23.
//

import SwiftUI

struct ParticipantsView: View {
    
    let damus_state: DamusState
    let original_pubkeys: [Pubkey]

    @Binding var filtered_pubkeys: Set<Pubkey>

    var body: some View {
        VStack {
            Text("Replying to", comment: "Text indicating that the view is used for editing which participants are replied to in a note.")
                .font(.headline)
            HStack {
                Spacer()
                
                Button {
                    // Remove all "p" refs, keep "e" refs
                    filtered_pubkeys = Set(original_pubkeys)
                } label: {
                    Text("Remove all", comment: "Button label to remove all participants from a note reply.")
                }
                .font(.footnote.weight(.bold))
                .frame(minWidth: 100, minHeight: 44)
                .foregroundColor(.white)
                .background(LINEAR_GRADIENT)
                .clipShape(Capsule())

                Button {
                    filtered_pubkeys = []
                } label: {
                    Text("Add all", comment: "Button label to re-add all original participants as profiles to reply to in a note")
                }
                .font(.footnote.weight(.bold))
                .frame(minWidth: 80, minHeight: 44)
                .foregroundColor(.white)
                .background(LINEAR_GRADIENT)
                .clipShape(Capsule())
                
                Spacer()
            }
            VStack {
                ScrollView {
                    ForEach(original_pubkeys) { pubkey in
                        HStack {
                            UserView(damus_state: damus_state, pubkey: pubkey)
                            
                            Image("check-circle.fill")
                                .font(.title)
                                .foregroundColor(filtered_pubkeys.contains(pubkey) ? .gray : DamusColors.purple)
                        }
                        .onTapGesture {
                            if filtered_pubkeys.contains(pubkey) {
                                filtered_pubkeys.remove(pubkey)
                            } else {
                                filtered_pubkeys.insert(pubkey)
                            }
                        }
                    }                    
                }
            }
            Spacer()
        }
        .padding()
    }
}
