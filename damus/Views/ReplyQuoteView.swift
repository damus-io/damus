//
//  SwiftUIView.swift
//  damus
//
//  Created by William Casarin on 2022-04-19.
//

import SwiftUI

struct ReplyQuoteView: View {
    let quoter: NostrEvent
    let event_id: String
    
    @EnvironmentObject var profiles: Profiles
    @EnvironmentObject var thread: ThreadModel
    
    func MainContent(event: NostrEvent) -> some View {
        HStack(alignment: .top) {
            ProfilePicView(picture: profiles.lookup(id: event.pubkey)?.picture, size: 16, highlight: .none)
            //.border(Color.blue)
            
            VStack {
                HStack {
                    ProfileName(pubkey: event.pubkey, profile: profiles.lookup(id: event.pubkey))
                    Text("\(format_relative_time(event.created_at))")
                        .foregroundColor(.gray)
                    Spacer()
                }
                
                Text(event.content)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                
                //Spacer()
            }
            //.border(Color.red)
        }
        //.border(Color.green)
    }
    
    var body: some View {
        Group {
            if let event = thread.lookup(event_id) {
                MainContent(event: event)
                .padding(4)
                .frame(maxHeight: 100)
                .background(event.id == thread.event!.id ? Color.red.opacity(0.2) : Color.secondary.opacity(0.2))
                .cornerRadius(8.0)
                .contentShape(Rectangle())
                .onTapGesture {
                    thread.set_active_event(event)
                }
            } else {
                ProgressView()
                    .progressViewStyle(.circular)
            }
        }
    }
}

/*
struct SwiftUIView_Previews: PreviewProvider {
    static var previews: some View {
        SwiftUIView()
    }
}
 */
