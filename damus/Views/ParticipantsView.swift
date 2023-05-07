//
//  ParticipantsView.swift
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
            Text("Replying to", comment: "Text indicating that the view is used for editing which participants are replied to in a note.")
                .font(.headline)
            HStack {
                Spacer()
                
                Button {
                    // Remove all "p" refs, keep "e" refs
                    references = originalReferences.eRefs
                } label: {
                    Text("Remove all", comment: "Button label to remove all participants from a note reply.")
                }
                .font(.system(size: 14, weight: .bold))
                .frame(width: 100, height: 30)
                .foregroundColor(.white)
                .background(LINEAR_GRADIENT)
                .clipShape(Capsule())

                Button {
                    references = originalReferences
                } label: {
                    Text("Add all", comment: "Button label to re-add all original participants as profiles to reply to in a note")
                }
                .font(.system(size: 14, weight: .bold))
                .frame(width: 80, height: 30)
                .foregroundColor(.white)
                .background(LINEAR_GRADIENT)
                .clipShape(Capsule())
                
                Spacer()
            }
            VStack {
                ScrollView {
                    ForEach(originalReferences.pRefs) { participant in
                        let pubkey = participant.id
                        HStack {
                            ProfilePicView(pubkey: pubkey, size: PFP_SIZE, highlight: .none, profiles: damus_state.profiles, disable_animation: damus_state.settings.disable_animation)
                            
                            VStack(alignment: .leading) {
                                let profile = damus_state.profiles.lookup(id: pubkey)
                                ProfileName(pubkey: pubkey, profile: profile, damus: damus_state, show_nip5_domain: false)
                                if let about = profile?.about {
                                    Text(FollowUserView.markdown.process(about))
                                        .lineLimit(3)
                                        .font(.footnote)
                                }
                            }
                            
                            Spacer()
                            
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 30))
                                .foregroundColor(references.contains(participant) ? DamusColors.purple : .gray)
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
            }
            Spacer()
        }
        .padding()
    }
}
