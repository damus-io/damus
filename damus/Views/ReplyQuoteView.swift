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
    let image_cache: ImageCache
    
    @EnvironmentObject var profiles: Profiles
    @EnvironmentObject var thread: ThreadModel
    
    func MainContent(event: NostrEvent) -> some View {
        HStack(alignment: .top) {
            Rectangle().frame(width: 2)
                .padding([.leading], 4)
                .foregroundColor(.accentColor)
            
            VStack(alignment: .leading) {
                HStack(alignment: .top) {
                    ProfilePicView(picture: profiles.lookup(id: event.pubkey)?.picture, size: 16, highlight: .reply, image_cache: image_cache)
                    Text(Profile.displayName(profile: profiles.lookup(id: event.pubkey), pubkey: event.pubkey))
                        .foregroundColor(.accentColor)
                    Text("\(format_relative_time(event.created_at))")
                        .foregroundColor(.gray)
                }
                
                Text(event.content)
                    //.frame(maxWidth: .infinity, alignment: .leading)
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
                .contentShape(Rectangle())
                .onTapGesture {
                    NotificationCenter.default.post(name: .select_quote, object: event)
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
