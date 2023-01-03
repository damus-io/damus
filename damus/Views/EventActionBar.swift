//
//  EventActionBar.swift
//  damus
//
//  Created by William Casarin on 2022-04-16.
//

import SwiftUI
import UIKit

let ICON_SIZE: CGFloat = 15

enum ActionBarSheet: Identifiable {
    case reply

    var id: String {
        switch self {
        case .reply: return "reply"
        }
    }
}

struct EventActionBar: View {
    let damus_state: DamusState
    let event: NostrEvent
    let generator = UIImpactFeedbackGenerator(style: .medium)
    @State var sheet: ActionBarSheet? = nil
    @State var confirm_boost: Bool = false
    @StateObject var bar: ActionBarModel
    
    var body: some View {
        HStack {
            /*
            EventActionButton(img: "ic-share") {
                print("share")
            }
            */
            
            //Spacer()
            
            if damus_state.keypair.privkey != nil {
                EventActionButton(img: "ic-reply", highlighted: false) {
                    notify(.reply, event)
                }
            }
            
            Spacer()
            
            HStack(alignment: .bottom) {
                Text("\(bar.boosts > 0 ? "\(bar.boosts)" : "")")
                    .font(.footnote.weight(.medium))
                    .foregroundColor(bar.boosted ? .accentColor : nil)
                
                EventActionButton(img: "ic-boost", highlighted: bar.boosted ? true : false) {
                    if bar.boosted {
                        notify(.delete, bar.our_boost)
                    } else {
                        self.confirm_boost = true
                    }
                }
            }
            
            Spacer()

            HStack(alignment: .bottom) {
                Text("\(bar.likes > 0 ? "\(bar.likes)" : "")")
                    .font(.footnote.weight(.medium))
                    .foregroundColor(bar.liked ? .accentColor : nil)
                    
                LikeButton(liked: bar.liked) {
                    if bar.liked {
                        notify(.delete, bar.our_like)
                    } else {
                        send_like()
                    }
                }
            }
            
            Spacer()
            
            /*
            HStack(alignment: .bottom) {
                Text("\(bar.tips > 0 ? "\(bar.tips)" : "")")
                    .font(.footnote)
                    .foregroundColor(bar.tipped ? .accentColor : nil)
                
                EventActionButton(img: "ic-lightning", highlighted: bar.tipped ? true : false) {
                    if bar.tipped {
                        //notify(.delete, bar.our_tip)
                    } else {
                        //notify(.boost, event)
                    }
                }
            }
            
            Spacer()
            */
            
        }
        .padding(.bottom, 5)
        .alert("Boost", isPresented: $confirm_boost) {
            Button("Cancel") {
                confirm_boost = false
            }
            Button("Boost") {
                send_boost()
            }
        } message: {
            Text("Are you sure you want to boost this post?")
        }
        .onReceive(handle_notify(.liked)) { n in
            let liked = n.object as! Counted
            if liked.id != event.id {
                return
            }
            self.bar.likes = liked.total
            if liked.event.pubkey == damus_state.keypair.pubkey {
                self.bar.our_like = liked.event
            }
        }
    }
    
    func send_boost() {
        guard let privkey = self.damus_state.keypair.privkey else {
            return
        }

        let boost = make_boost_event(pubkey: damus_state.keypair.pubkey, privkey: privkey, boosted: self.event)
        
        self.bar.our_boost = boost
        
        damus_state.pool.send(.event(boost))
    }
    
    func send_like() {
        guard let privkey = damus_state.keypair.privkey else {
            return
        }
        
        let like_ev = make_like_event(pubkey: damus_state.pubkey, privkey: privkey, liked: event)
        
        self.bar.our_like = like_ev

        generator.impactOccurred()
        
        damus_state.pool.send(.event(like_ev))
    }
}


func EventActionButton(img: String, highlighted: Bool, action: @escaping () -> ()) -> some View {
    Button(action: action) {
        if highlighted {
            // Show the selected item as highlighted
            LinearGradient(gradient: Gradient(colors: [
                Color(red: 0.8, green: 0.263, blue: 0.773),
                Color(red: 0.224, green: 0.302, blue: 0.886)
            ]), startPoint: .topTrailing, endPoint: .bottomTrailing)
                .mask(Image(img)
                    .resizable()
                    .contentShape(Rectangle())
                    .frame(width: ICON_SIZE, height: ICON_SIZE)
            )
            .contentShape(Rectangle())
            .frame(width: ICON_SIZE, height: ICON_SIZE)
        } else {
            Image(img)
                .resizable()
                .contentShape(Rectangle())
                .frame(width: ICON_SIZE, height: ICON_SIZE)
        }    }
    //.padding(.trailing, 40)
}

struct LikeButton: View {
    let liked: Bool
    let action: () -> ()
    
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        Button(action: action) {
            if liked {
                // Show the selected item as highlighted
                LinearGradient(gradient: Gradient(colors: [
                    Color(red: 0.8, green: 0.263, blue: 0.773),
                    Color(red: 0.224, green: 0.302, blue: 0.886)
                ]), startPoint: .topTrailing, endPoint: .bottomTrailing)
                    .mask(Image("ic-like")
                        .resizable()
                        .contentShape(Rectangle())
                        .frame(width: ICON_SIZE, height: ICON_SIZE)
                )
                .contentShape(Rectangle())
                .frame(width: ICON_SIZE, height: ICON_SIZE)
            } else {
                Image("ic-like")
                    .resizable()
                    .contentShape(Rectangle())
                    .frame(width: ICON_SIZE, height: ICON_SIZE)
            }
        }
    }
}


struct EventActionBar_Previews: PreviewProvider {
    static var previews: some View {
        let pk = "pubkey"
        let ds = test_damus_state()
        let bar = ActionBarModel(likes: 0, boosts: 0, tips: 0, our_like: nil, our_boost: nil, our_tip: nil)
        let ev = NostrEvent(content: "hi", pubkey: pk)
        EventActionBar(damus_state: ds, event: ev, bar: bar)
    }
}
