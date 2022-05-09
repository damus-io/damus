//
//  EventActionBar.swift
//  damus
//
//  Created by William Casarin on 2022-04-16.
//

import SwiftUI

enum ActionBarSheet: Identifiable {
    case reply

    var id: String {
        switch self {
        case .reply: return "reply"
        }
    }
}

struct EventActionBar: View {
    let event: NostrEvent
    let our_pubkey: String
    @State var sheet: ActionBarSheet? = nil
    let profiles: Profiles
    @StateObject var bar: ActionBarModel
    
    var body: some View {
        HStack {
            /*
            EventActionButton(img: "square.and.arrow.up") {
                print("share")
            }

            Spacer()
            
             */
            EventActionButton(img: "bubble.left", col: nil) {
                notify(.reply, event)
            }
            .padding([.trailing], 40)

            HStack(alignment: .bottom) {
                Text("\(bar.likes > 0 ? "\(bar.likes)" : "")")
                    .font(.footnote)
                    .foregroundColor(Color.gray)
                    
                EventActionButton(img: bar.liked ? "heart.fill" : "heart", col: bar.liked ? Color.red : nil) {
                    if bar.liked {
                        notify(.delete, bar.our_like)
                    } else {
                        notify(.like, event)
                    }
                }
            }
            .padding([.trailing], 40)

            EventActionButton(img: "arrow.2.squarepath", col: bar.boosted ? Color.green : nil) {
                if bar.boosted {
                    notify(.delete, bar.our_boost)
                } else {
                    notify(.boost, event)
                }
            }

        }
        .onReceive(handle_notify(.liked)) { n in
            let liked = n.object as! Liked
            if liked.id != event.id {
                return
            }
            self.bar.likes = liked.total
            if liked.like.pubkey == our_pubkey {
                self.bar.our_like = liked.like
            }
        }
    }
}


func EventActionButton(img: String, col: Color?, action: @escaping () -> ()) -> some View {
    Button(action: action) {
        Label("", systemImage: img)
            .font(.footnote)
            .foregroundColor(col == nil ? Color.gray : col!)
    }
}

