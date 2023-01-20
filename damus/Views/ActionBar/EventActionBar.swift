//
//  EventActionBar.swift
//  damus
//
//  Created by William Casarin on 2022-04-16.
//

import SwiftUI
import UIKit

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
    @State var show_share_sheet: Bool = false
    @StateObject var bar: ActionBarModel
    
    var body: some View {
        HStack {
            if damus_state.keypair.privkey != nil {
                EventActionButton(img: "bubble.left", col: nil) {
                    notify(.reply, event)
                }
            }
            Spacer()
            ZStack {
                
                EventActionButton(img: "arrow.2.squarepath", col: bar.boosted ? Color.green : nil) {
                    if bar.boosted {
                        notify(.delete, bar.our_boost)
                    } else if damus_state.is_privkey_user {
                        self.confirm_boost = true
                    }
                }
                Text("\(bar.boosts > 0 ? "\(bar.boosts)" : "")")
                    .offset(x: 18)
                    .font(.footnote.weight(.medium))
                    .foregroundColor(bar.boosted ? Color.green : Color.gray)
            }
            Spacer()
            ZStack {
                LikeButton(liked: bar.liked) {
                    if bar.liked {
                        notify(.delete, bar.our_like)
                    } else {
                        send_like()
                    }
                }
                Text("\(bar.likes > 0 ? "\(bar.likes)" : "")")
                    .offset(x: 22)
                    .font(.footnote.weight(.medium))
                    .foregroundColor(bar.liked ? Color.accentColor : Color.gray)
                
            }
            Spacer()
            EventActionButton(img: "square.and.arrow.up", col: Color.gray) {
                show_share_sheet = true
            }
        }
        .sheet(isPresented: $show_share_sheet) {
            if let note_id = bech32_note_id(event.id) {
                if let url = URL(string: "https://damus.io/" + note_id) {
                    ShareSheet(activityItems: [url])
                }
            }
        }
        .alert(NSLocalizedString("Repost", comment: "Title of alert for confirming to repost a post."), isPresented: $confirm_boost) {
            Button(NSLocalizedString("Cancel", comment: "Button to cancel out of reposting a post.")) {
                confirm_boost = false
            }
            Button(NSLocalizedString("Repost", comment: "Button to confirm reposting a post.")) {
                send_boost()
            }
        } message: {
            Text("Are you sure you want to repost this?", comment: "Alert message to ask if user wants to repost a post.")
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


func EventActionButton(img: String, col: Color?, action: @escaping () -> ()) -> some View {
    Button(action: action) {
        Label(NSLocalizedString("\u{00A0}", comment: "Non-breaking space character to fill in blank space next to event action button icons."), systemImage: img)
            .font(.footnote.weight(.medium))
            .foregroundColor(col == nil ? Color.gray : col!)
    }
}

struct LikeButton: View {
    let liked: Bool
    let action: () -> ()
    
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        Button(action: action) {
            Image(liked ? "shaka-full" : "shaka-line")
                .foregroundColor(liked ? .accentColor : .gray)
        }
    }
}


struct EventActionBar_Previews: PreviewProvider {
    static var previews: some View {
        let pk = "pubkey"
        let ds = test_damus_state()
        let ev = NostrEvent(content: "hi", pubkey: pk)
        
        let bar = ActionBarModel(likes: 0, boosts: 0, tips: 0, our_like: nil, our_boost: nil, our_tip: nil)
        let likedbar = ActionBarModel(likes: 10, boosts: 10, tips: 0, our_like: nil, our_boost: nil, our_tip: nil)
        let likedbar_ours = ActionBarModel(likes: 100, boosts: 100, tips: 0, our_like: NostrEvent(id: "", content: "", pubkey: ""), our_boost: nil, our_tip: nil)
        
        VStack(spacing: 50) {
            EventActionBar(damus_state: ds, event: ev, bar: bar)
            
            EventActionBar(damus_state: ds, event: ev, bar: likedbar)
            
            EventActionBar(damus_state: ds, event: ev, bar: likedbar_ours)
        }
        .padding(20)
    }
}
