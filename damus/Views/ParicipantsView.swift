//
//  ParicipantsView.swift
//  damus
//
//  Created by Joel Klabo on 1/18/23.
//

import SwiftUI

struct ParticipantsView: View {
    
    let damus: DamusState
    
    @Binding var references: [ReferencedId]
    @Binding var originalReferences: [ReferencedId]
    
    var body: some View {
        VStack {
            Text("Edit participants")
            HStack {
                Button {
                    // Remove all "p" refs, keep "e" refs
                    references = originalReferences.eRefs
                } label: {
                    Text("Remove all")
                }
                Button {
                    references = originalReferences
                } label: {
                    Text("Add all")
                }
            }
            ForEach(originalReferences.pRefs) { participant in
                HStack {
                    let pk = participant.ref_id
                    let prof = damus.profiles.lookup(id: pk)
                    Text(Profile.displayName(profile: prof, pubkey: pk))
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
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
            Spacer()
        }
        .padding()
    }
}
