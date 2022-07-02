//
//  SwiftUIView.swift
//  damus
//
//  Created by William Casarin on 2022-04-19.
//

import SwiftUI

struct ReplyQuoteView: View {
    let privkey: String?
    let quoter: NostrEvent
    let event_id: String
    let image_cache: ImageCache
    let profiles: Profiles
    
    @EnvironmentObject var thread: ThreadModel
    
    func MainContent(event: NostrEvent) -> some View {
        HStack(alignment: .top) {
            Rectangle()
                .frame(width: 2)
                .padding([.leading], 4)
                .foregroundColor(.accentColor)
            
            VStack(alignment: .leading) {
                HStack(alignment: .top) {
                    ProfilePicView(pubkey: event.pubkey, size: 16, highlight: .reply, image_cache: image_cache, profiles: profiles)
                    Text(Profile.displayName(profile: profiles.lookup(id: event.pubkey), pubkey: event.pubkey))
                        .foregroundColor(.accentColor)
                    Text("\(format_relative_time(event.created_at))")
                        .foregroundColor(.gray)
                }
                
                NoteContentView(privkey: privkey, event: event, profiles: profiles, content: event.content)
                    .font(.callout)
                    .foregroundColor(.accentColor)
                
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
                .frame(maxWidth: .infinity, alignment: .leading)
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

struct ReplyQuoteView_Previews: PreviewProvider {
    static var previews: some View {
        let s = test_damus_state()
        let quoter = NostrEvent(content: "a\nb\nc", pubkey: "pubkey")
        ReplyQuoteView(privkey: s.keypair.privkey, quoter: quoter, event_id: "pubkey2", image_cache: s.image_cache, profiles: s.profiles)
            .environmentObject(ThreadModel(event: quoter, pool: s.pool, privkey: s.keypair.privkey))
    }
}
