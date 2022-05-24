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
    let keypair: Keypair
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
            if keypair.privkey != nil {
                EventActionButton(img: "bubble.left", col: nil) {
                    notify(.reply, event)
                }
                .padding([.trailing], 20)
            }

            HStack(alignment: .bottom) {
                Text("\(bar.likes > 0 ? "\(bar.likes)" : "")")
                    .font(.footnote)
                    .foregroundColor(bar.liked ? Color.red : Color.gray)
                    
                EventActionButton(img: bar.liked ? "heart.fill" : "heart", col: bar.liked ? Color.red : nil) {
                    if bar.liked {
                        notify(.delete, bar.our_like)
                    } else {
                        notify(.like, event)
                    }
                }
            }
            .padding([.trailing], 20)

            HStack(alignment: .bottom) {
                Text("\(bar.boosts > 0 ? "\(bar.boosts)" : "")")
                    .font(.footnote)
                    .foregroundColor(bar.boosted ? Color.green : Color.gray)
                
                EventActionButton(img: "arrow.2.squarepath", col: bar.boosted ? Color.green : nil) {
                    if bar.boosted {
                        notify(.delete, bar.our_boost)
                    } else {
                        notify(.boost, event)
                    }
                }
            }
            .padding([.trailing], 20)
            
            HStack(alignment: .bottom) {
                Text("\(bar.tips > 0 ? "\(bar.tips)" : "")")
                    .font(.footnote)
                    .foregroundColor(bar.tipped ? Color.orange : Color.gray)
                
                EventActionButton(img: bar.tipped ? "bitcoinsign.circle.fill" : "bitcoinsign.circle", col: bar.tipped ? Color.orange : nil) {
                    if bar.tipped {
                        notify(.delete, bar.our_tip)
                    } else {
                        notify(.boost, event)
                    }
                }
            }

        }
        .onReceive(handle_notify(.liked)) { n in
            let liked = n.object as! Counted
            if liked.id != event.id {
                return
            }
            self.bar.likes = liked.total
            if liked.event.pubkey == keypair.pubkey {
                self.bar.our_like = liked.event
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

