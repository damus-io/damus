//
//  TimelineView.swift
//  damus
//
//  Created by William Casarin on 2022-04-18.
//

import SwiftUI

struct TimelineView: View {
    @Binding var events: [NostrEvent]
    @EnvironmentObject var profiles: Profiles
    
    let pool: RelayPool
    
    var body: some View {
        ScrollView {
            LazyVStack {
                ForEach(events, id: \.id) { (ev: NostrEvent) in
                    /*
                    let evdet = EventDetailView(thread: ThreadModel(event: ev, pool: pool))
                        .navigationBarTitle("Thread")
                        .padding([.leading, .trailing], 6)
                        .environmentObject(profiles)
                     */
                    
                    let evdet = ThreadView(thread: ThreadModel(event: ev, pool: pool))
                        .navigationBarTitle("Chat")
                        .padding([.leading, .trailing], 6)
                        .environmentObject(profiles)
                    
                    NavigationLink(destination: evdet) {
                        EventView(event: ev, highlight: .none, has_action_bar: true)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
        .padding([.leading, .trailing], 6)
        .environmentObject(profiles)
    }
}

/*
struct TimelineView_Previews: PreviewProvider {
    static var previews: some View {
        TimelineView()
    }
}
 */
