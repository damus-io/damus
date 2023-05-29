//
//  EventActionBar.swift
//  damus
//
//  Created by William Casarin on 2022-04-16.
//

import SwiftUI
import UIKit


struct EventActionBar: View {
    let damus_state: DamusState
    let event: NostrEvent
    let generator = UIImpactFeedbackGenerator(style: .medium)
    
    // just used for previews
    @State var show_share_sheet: Bool = false
    @State var show_share_action: Bool = false
    @State var show_repost_action: Bool = false

    @ObservedObject var bar: ActionBarModel
    
    init(damus_state: DamusState, event: NostrEvent, bar: ActionBarModel? = nil) {
        self.damus_state = damus_state
        self.event = event
        _bar = ObservedObject(wrappedValue: bar ?? make_actionbar_model(ev: event.id, damus: damus_state))
    }
    
    var lnurl: String? {
        damus_state.profiles.lookup(id: event.pubkey)?.lnurl
    }
    
    var show_like: Bool {
        if damus_state.settings.onlyzaps_mode {
            return false
        }
        
        return true
    }
    
    var body: some View {
        HStack {
            if damus_state.keypair.privkey != nil {
                HStack(spacing: 4) {
                    EventActionButton(img: "bubble.left", col: bar.replied ? DamusColors.purple : Color.gray) {
                        notify(.compose, PostAction.replying_to(event))
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
                        self.show_repost_action = true
                    }
                }
                .accessibilityLabel(NSLocalizedString("Boosts", comment: "Accessibility label for boosts button"))
                Text(verbatim: "\(bar.boosts > 0 ? "\(bar.boosts)" : "")")
                    .font(.footnote.weight(.medium))
                    .foregroundColor(bar.boosted ? Color.green : Color.gray)
            }

            if show_like {
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
            }

            if let lnurl = self.lnurl {
                Spacer()
                ZapButton(damus_state: damus_state, event: event, lnurl: lnurl, zaps: self.damus_state.events.get_cache_data(self.event.id).zaps_model)
            }

            Spacer()
            EventActionButton(img: "square.and.arrow.up", col: Color.gray) {
                show_share_action = true
            }
            .accessibilityLabel(NSLocalizedString("Share", comment: "Button to share a post"))
        }
        .onAppear {
            self.bar.update(damus: damus_state, evid: self.event.id)
        }
        .sheet(isPresented: $show_share_action, onDismiss: { self.show_share_action = false }) {
            if #available(iOS 16.0, *) {
                ShareAction(event: event, bookmarks: damus_state.bookmarks, show_share: $show_share_sheet)
                    .presentationDetents([.height(300)])
                    .presentationDragIndicator(.visible)
            } else {
                ShareAction(event: event, bookmarks: damus_state.bookmarks, show_share: $show_share_sheet)
            }
        }
        .sheet(isPresented: $show_share_sheet, onDismiss: { self.show_share_sheet = false }) {
            if let note_id = bech32_note_id(event.id) {
                if let url = URL(string: "https://damus.io/" + note_id) {
                    ShareSheet(activityItems: [url])
                }
            }
        }
        .sheet(isPresented: $show_repost_action, onDismiss: { self.show_repost_action = false }) {
        
            if #available(iOS 16.0, *) {
                RepostAction(damus_state: self.damus_state, event: event)
                    .presentationDetents([.height(220)])
                    .presentationDragIndicator(.visible)
            } else {
                RepostAction(damus_state: self.damus_state, event: event)
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
        let mega_max_bar = ActionBarModel(likes: 9999999, boosts: 99999, zaps: 9999, zap_total: 99999999, replies: 9999999,  our_like: test_event, our_boost: test_event, our_zap: .zap(test_zap), our_reply: test_event)
        
        VStack(spacing: 50) {
            EventActionBar(damus_state: ds, event: ev, bar: bar)
            
            EventActionBar(damus_state: ds, event: ev, bar: likedbar)
            
            EventActionBar(damus_state: ds, event: ev, bar: likedbar_ours)
            
            EventActionBar(damus_state: ds, event: ev, bar: maxed_bar)
            
            EventActionBar(damus_state: ds, event: ev, bar: extra_max_bar)

            EventActionBar(damus_state: ds, event: ev, bar: mega_max_bar)
        }
        .padding(20)
    }
}
