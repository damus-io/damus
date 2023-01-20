//
//  ParicipantsView.swift
//  damus
//
//  Created by Joel Klabo on 1/18/23.
//

import SwiftUI

struct ParticipantsView: View {
    
    let damus_state: DamusState
    
    @Binding var references: [ReferencedId]
    @Binding var originalReferences: [ReferencedId]
    
    var body: some View {
        VStack {
            Text("Edit participants")
            HStack {
                Spacer()
                Button {
                    // Remove all "p" refs, keep "e" refs
                    references = originalReferences.eRefs
                } label: {
                    Text("Remove all")
                }
                .buttonStyle(.borderedProminent)
                Spacer()
                Button {
                    references = originalReferences
                } label: {
                    Text("Add all")
                }
                .buttonStyle(.borderedProminent)
                Spacer()
            }
            VStack {
                ForEach(originalReferences.pRefs) { participant in
                    let pubkey = participant.id
                    HStack {
                        ProfilePicView(pubkey: pubkey, size: PFP_SIZE, highlight: .none, profiles: damus_state.profiles)
                        
                        VStack(alignment: .leading) {
                            let profile = damus_state.profiles.lookup(id: pubkey)
                            ProfileName(pubkey: pubkey, profile: profile, damus: damus_state, show_friend_confirmed: false, show_nip5_domain: false)
                            if let about = profile?.about {
                                Text(FollowUserView.markdown.process(about))
                                    .lineLimit(3)
                                    .font(.footnote)
                            }
                        }
                        
                        Spacer()
                        
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 30))
                            .foregroundColor(references.contains(participant) ? .purple : .gray)
                    }
                    .onTapGesture {
                        if references.contains(participant) {
                            references = references.filter {
                                $0 != participant
                            }
                        } else {
                            if references.contains(participant) {
                                // Don't add it twice
                            } else {
                                references.append(participant)
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
