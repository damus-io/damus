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
    let test_lnurl: String?
    let generator = UIImpactFeedbackGenerator(style: .medium)
    
    // just used for previews
    @State var sheet: ActionBarSheet? = nil
    @State var show_share_sheet: Bool = false
    @State var show_share_action: Bool = false
    
    @ObservedObject var bar: ActionBarModel
    
    @Environment(\.colorScheme) var colorScheme
    
    init(damus_state: DamusState, event: NostrEvent, bar: ActionBarModel? = nil, test_lnurl: String? = nil) {
        self.damus_state = damus_state
        self.event = event
        self.test_lnurl = test_lnurl
        _bar = ObservedObject(wrappedValue: bar ?? make_actionbar_model(ev: event.id, damus: damus_state))
    }
    
    var lnurl: String? {
        test_lnurl ?? damus_state.profiles.lookup(id: event.pubkey)?.lnurl
    }
    
    var body: some View {
        HStack {
            if damus_state.keypair.privkey != nil {
                HStack(spacing: 4) {
                    EventActionButton(img: "bubble.left", col: bar.replied ? DamusColors.purple : Color.gray) {
                        notify(.reply, event)
                    }
                    .accessibilityLabel(NSLocalizedString("Reply", comment: "Accessibility label for reply button"))
                    Text(verbatim: "\(bar.replies > 0 ? "\(bar.replies)" : "")")
                        .font(.footnote.weight(.medium))
                        .foregroundColor(bar.replied ? DamusColors.purple : Color.gray)
                }
            }
            Spacer()
            HStack(spacing: 4) {
                
                EventActionButton(img: "arrow.2.squarepath", col: bar.boosted ? Color.green : nil) {
                    if bar.boosted {
                        notify(.delete, bar.our_boost)
                    } else {
                        send_boost()
                    }
                }
                .accessibilityLabel(NSLocalizedString("Boosts", comment: "Accessibility label for boosts button"))
                Text(verbatim: "\(bar.boosts > 0 ? "\(bar.boosts)" : "")")
                    .font(.footnote.weight(.medium))
                    .foregroundColor(bar.boosted ? Color.green : Color.gray)
            }
            Spacer()
            
            HStack(spacing: 4) {
                LikeButton(liked: bar.liked) {
                    if bar.liked {
                        notify(.delete, bar.our_like)
                    } else {
                        send_like()
                    }
                }
                
                Text(verbatim: "\(bar.likes > 0 ? "\(bar.likes)" : "")")
                    .font(.footnote.weight(.medium))
                    .nip05_colorized(gradient: bar.liked)
            }
            
            if let lnurl = self.lnurl {
                Spacer()
                ZapButton(damus_state: damus_state, event: event, lnurl: lnurl, bar: bar)
            }

            Spacer()
            EventActionButton(img: "square.and.arrow.up", col: Color.gray) {
                show_share_action = true
            }
            .accessibilityLabel(NSLocalizedString("Share", comment: "Button to share a post"))
        }
        .sheet(isPresented: $show_share_action) {
            if #available(iOS 16.0, *) {
                ShareAction(event: event, bookmarks: damus_state.bookmarks, show_share_sheet: $show_share_sheet, show_share_action: $show_share_action)
                    .presentationDetents([.height(300)])
                    .presentationDragIndicator(.visible)
            } else {
                if let note_id = bech32_note_id(event.id) {
                    if let url = URL(string: "https://damus.io/" + note_id) {
                        ShareSheet(activityItems: [url])
                    }
                }
            }
        }
        .sheet(isPresented: $show_share_sheet) {
            if let note_id = bech32_note_id(event.id) {
                if let url = URL(string: "https://damus.io/" + note_id) {
                    ShareSheet(activityItems: [url])
                }
            }
        }
        .onReceive(handle_notify(.update_stats)) { n in
            let target = n.object as! String
            guard target == self.event.id else { return }
            self.bar.update(damus: self.damus_state, evid: target)
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
        
        notify(.boost, boost)
    }
    
    func send_like() {
        guard let privkey = damus_state.keypair.privkey else {
            return
        }
        
        let like_ev = make_like_event(pubkey: damus_state.pubkey, privkey: privkey, liked: event)
        
        self.bar.our_like = like_ev

        generator.impactOccurred()
        
        damus_state.postbox.send(like_ev)
    }
}


func EventActionButton(img: String, col: Color?, action: @escaping () -> ()) -> some View {
    Button(action: action) {
        Image(systemName: img)
            .foregroundColor(col == nil ? Color.gray : col!)
            .font(.footnote.weight(.medium))
    }
}

struct LikeButton: View {
    let liked: Bool
    let action: () -> ()
    
    @Environment(\.colorScheme) var colorScheme

    // Following four are Shaka animation properties
    let timer = Timer.publish(every: 0.10, on: .main, in: .common).autoconnect()
    @State private var shouldAnimate = false
    @State private var rotationAngle = 0.0
    @State private var amountOfAngleIncrease: Double = 0.0
    
    var body: some View {

        Button(action: {
            withAnimation(Animation.easeOut(duration: 0.15)) {
                self.action()
                shouldAnimate = true
                amountOfAngleIncrease = 20.0
            }
        }) {
            if liked {
                LINEAR_GRADIENT
                    .mask(Image("shaka-full")
                        .resizable()
                    ).frame(width: 14, height: 14)
            } else {
                Image("shaka-line")
                    .foregroundColor(.gray)
            }
        }
        .accessibilityLabel(NSLocalizedString("Like", comment: "Accessibility Label for Like button"))
        .rotationEffect(Angle(degrees: shouldAnimate ? rotationAngle : 0))
        .onReceive(self.timer) { _ in
            // Shaka animation logic
            rotationAngle = amountOfAngleIncrease
            if amountOfAngleIncrease == 0 {
                timer.upstream.connect().cancel()
                return
            }
            amountOfAngleIncrease = -amountOfAngleIncrease
            if amountOfAngleIncrease < 0 {
                amountOfAngleIncrease += 2.5
            } else {
                amountOfAngleIncrease -= 2.5
            }
        }
    }
}


struct EventActionBar_Previews: PreviewProvider {
    static var previews: some View {
        let pk = "pubkey"
        let ds = test_damus_state()
        let ev = NostrEvent(content: "hi", pubkey: pk)
        
        let bar = ActionBarModel.empty()
        let likedbar = ActionBarModel(likes: 10, boosts: 0, zaps: 0, zap_total: 0, replies: 0, our_like: nil, our_boost: nil, our_zap: nil, our_reply: nil)
        let likedbar_ours = ActionBarModel(likes: 10, boosts: 0, zaps: 0, zap_total: 0, replies: 0, our_like: test_event, our_boost: nil, our_zap: nil, our_reply: nil)
        let maxed_bar = ActionBarModel(likes: 999, boosts: 999, zaps: 999, zap_total: 99999999, replies: 999, our_like: test_event, our_boost: test_event, our_zap: nil, our_reply: nil)
        let extra_max_bar = ActionBarModel(likes: 9999, boosts: 9999, zaps: 9999, zap_total: 99999999, replies: 9999, our_like: test_event, our_boost: test_event, our_zap: nil, our_reply: test_event)
        let mega_max_bar = ActionBarModel(likes: 9999999, boosts: 99999, zaps: 9999, zap_total: 99999999, replies: 9999999,  our_like: test_event, our_boost: test_event, our_zap: test_zap, our_reply: test_event)
        let zapbar = ActionBarModel(likes: 0, boosts: 0, zaps: 5, zap_total: 10000000, replies: 0, our_like: nil, our_boost: nil, our_zap: nil, our_reply: nil)
        
        VStack(spacing: 50) {
            EventActionBar(damus_state: ds, event: ev, bar: bar)
            
            EventActionBar(damus_state: ds, event: ev, bar: likedbar)
            
            EventActionBar(damus_state: ds, event: ev, bar: likedbar_ours)
            
            EventActionBar(damus_state: ds, event: ev, bar: maxed_bar)
            
            EventActionBar(damus_state: ds, event: ev, bar: extra_max_bar)

            EventActionBar(damus_state: ds, event: ev, bar: mega_max_bar)
            
            EventActionBar(damus_state: ds, event: ev, bar: zapbar, test_lnurl: "lnurl")
        }
        .padding(20)
    }
}
