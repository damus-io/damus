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
            ForEach(originalParticipants) { participant in
                ParticipantView(damus: damus, participant: participant) { participant, added in
                    if added {
                        participants.append(participant)
                    } else {
                        participants = participants.filter { $0 != participant }
                    }
                }
            }
        }
    }
}

struct ParticipantView: View {
    let damus: DamusState
    let participant: ReferencedId
    let onRemove: (ReferencedId, Bool) -> ()
    
    @State var isParticipating: Bool = true
    
    var body: some View {
        HStack {
            let pk = participant.ref_id
            let prof = damus.profiles.lookup(id: pk)
            Text(Profile.displayName(profile: prof, pubkey: pk))
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(isParticipating ? .purple : .gray)
        }
        .onTapGesture {
            isParticipating.toggle()
            onRemove(participant, isParticipating)
        }
    }
}
