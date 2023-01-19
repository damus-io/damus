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
                HStack {
                    let pk = participant.ref_id
                    let prof = damus.profiles.lookup(id: pk)
                    Text(Profile.displayName(profile: prof, pubkey: pk))
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(participants.contains(participant) ? .purple : .gray)
                }
                .onTapGesture {
                    if participants.contains(participant) {
                        participants = participants.filter {
                            $0 != participant
                        }
                    } else {
                        participants.append(participant)
                    }
                }
            }
            Spacer()
        }
        .padding()
    }
}

struct ParticipantView: View {
    let damus: DamusState
    let participant: ReferencedId
    
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
        }
    }
}
