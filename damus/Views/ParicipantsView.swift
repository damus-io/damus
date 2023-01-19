//
//  ParicipantsView.swift
//  damus
//
//  Created by Joel Klabo on 1/18/23.
//

import SwiftUI

struct ParticipantsView: View {
    
    let damus: DamusState
    
    @Binding var participants: [ReferencedId]
    @Binding var originalParticipants: [ReferencedId]
    
    var body: some View {
        VStack {
            Text("Edit participants")
            HStack {
                Button {
                    participants = []
                } label: {
                    Text("Remove all")
                }
                Button {
                    participants = originalParticipants
                } label: {
                    Text("Add all")
                }
            }
            ForEach(originalParticipants) { participant in
                ParticipantView(damus_state: damus, participant: participant, participants: $participants)
            }
            Spacer()
        }
        .padding()
    }
}


struct ParticipantView: View {
    let damus_state: DamusState
    let participant: ReferencedId
    
    @Binding var participants: [ReferencedId]
    @State var participating: Bool = true
    
    
    var pubkey: String {
        participant.id
    }
    
    var body: some View {
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
                .foregroundColor(participating ? .purple : .gray)
        }
        .onTapGesture {
            if participants.contains(participant) {
                participants = participants.filter {
                    $0 != participant
                }
                participating = false
            } else {
                participants.append(participant)
                participating = true
            }
        }
    }
}
