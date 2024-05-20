//
//  EventActionBar.swift
//  damus
//
//  Created by William Casarin on 2022-04-16.
//

import SwiftUI
import MCEmojiPicker

struct EventActionBar: View {
    let damus_state: DamusState
    let event: NostrEvent
    let generator = UIImpactFeedbackGenerator(style: .medium)
    let userProfile : ProfileModel
    
    // just used for previews
    @State var show_share_sheet: Bool = false
    @State var show_share_action: Bool = false
    @State var show_repost_action: Bool = false

    @State private var isOnTopHalfOfScreen: Bool = false

    @ObservedObject var bar: ActionBarModel
    
    init(damus_state: DamusState, event: NostrEvent, bar: ActionBarModel? = nil) {
        self.damus_state = damus_state
        self.event = event
        _bar = ObservedObject(wrappedValue: bar ?? make_actionbar_model(ev: event.id, damus: damus_state))
        self.userProfile = ProfileModel(pubkey: event.pubkey, damus: damus_state)
    }
    
    var lnurl: String? {
        damus_state.profiles.lookup_with_timestamp(event.pubkey)?.map({ pr in
            pr?.lnurl
        }).value
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
                    EventActionButton(img: "bubble2", col: bar.replied ? DamusColors.purple : Color.gray) {
                        notify(.compose(.replying_to(event)))
                    }
                    .accessibilityLabel(NSLocalizedString("Reply", comment: "Accessibility label for reply button"))
                    Text(verbatim: "\(bar.replies > 0 ? "\(bar.replies)" : "")")
                        .font(.footnote.weight(.medium))
                        .foregroundColor(bar.replied ? DamusColors.purple : Color.gray)
                }
            }
            Spacer()
            HStack(spacing: 4) {
                
                EventActionButton(img: "repost", col: bar.boosted ? Color.green : nil) {
                    self.show_repost_action = true
                }
                .accessibilityLabel(NSLocalizedString("Reposts", comment: "Accessibility label for boosts button"))
                Text(verbatim: "\(bar.boosts > 0 ? "\(bar.boosts)" : "")")
                    .font(.footnote.weight(.medium))
                    .foregroundColor(bar.boosted ? Color.green : Color.gray)
            }

            if show_like {
                Spacer()

                HStack(spacing: 4) {
                    LikeButton(damus_state: damus_state, liked: bar.liked, liked_emoji: bar.our_like != nil ? to_reaction_emoji(ev: bar.our_like!) : nil, isOnTopHalfOfScreen: $isOnTopHalfOfScreen) { emoji in
                        if bar.liked {
                            //notify(.delete, bar.our_like)
                        } else {
                            send_like(emoji: emoji)
                        }
                    }
                    .accessibilityLabel(Text("Likes", comment: "Accessibility label for like button"))
                    .accessibilityHint(Text("When like button is long pressed, it displays the multiple emojis overlay."))



                    Text(verbatim: "\(bar.likes > 0 ? "\(bar.likes)" : "")")
                        .font(.footnote.weight(.medium))
                        .nip05_colorized(gradient: bar.liked)
                }
            }

            if let lnurl = self.lnurl {
                Spacer()
                NoteZapButton(damus_state: damus_state, target: ZapTarget.note(id: event.id, author: event.pubkey), lnurl: lnurl, zaps: self.damus_state.events.get_cache_data(self.event.id).zaps_model)
            }

            Spacer()
            EventActionButton(img: "upload", col: Color.gray) {
                show_share_action = true
            }
            .accessibilityLabel(NSLocalizedString("Share", comment: "Button to share a note"))
        }
        .onAppear {
            self.bar.update(damus: damus_state, evid: self.event.id)
        }
        .sheet(isPresented: $show_share_action, onDismiss: { self.show_share_action = false }) {
            if #available(iOS 16.0, *) {
                ShareAction(event: event, bookmarks: damus_state.bookmarks, show_share: $show_share_sheet, userProfile: userProfile)
                    .presentationDetents([.height(300)])
                    .presentationDragIndicator(.visible)
            } else {
                ShareAction(event: event, bookmarks: damus_state.bookmarks, show_share: $show_share_sheet, userProfile: userProfile)
            }
        }
        .sheet(isPresented: $show_share_sheet, onDismiss: { self.show_share_sheet = false }) {
            ShareSheet(activityItems: [URL(string: "https://damus.io/" + event.id.bech32)!])
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
        .onReceive(handle_notify(.update_stats)) { target in
            guard target == self.event.id else { return }
            self.bar.update(damus: self.damus_state, evid: target)
        }
        .onReceive(handle_notify(.liked)) { liked in
            if liked.id != event.id {
                return
            }
            self.bar.likes = liked.total
            if liked.event.pubkey == damus_state.keypair.pubkey {
                self.bar.our_like = liked.event
            }
        }
        .background(
            GeometryReader { geometry in
                EmptyView()
                    .onAppear {
                        let eventActionBarY = geometry.frame(in: .global).midY
                        let screenMidY = UIScreen.main.bounds.midY
                        self.isOnTopHalfOfScreen = eventActionBarY > screenMidY
                    }
                    .onChange(of: geometry.frame(in: .global).midY) { newY in
                        let screenMidY = UIScreen.main.bounds.midY
                        self.isOnTopHalfOfScreen = newY > screenMidY
                    }
            }
        )
    }

    func send_like(emoji: String) {
        guard let keypair = damus_state.keypair.to_full(),
              let like_ev = make_like_event(keypair: keypair, liked: event, content: emoji) else {
            return
        }

        self.bar.our_like = like_ev

        generator.impactOccurred()
        
        damus_state.postbox.send(like_ev)
    }
}


func EventActionButton(img: String, col: Color?, action: @escaping () -> ()) -> some View {
    Image(img)
        .resizable()
        .foregroundColor(col == nil ? Color.gray : col!)
        .font(.footnote.weight(.medium))
        .aspectRatio(contentMode: .fit)
        .frame(width: 20, height: 20)
        .onTapGesture {
            action()
        }
}

struct LikeButton: View {
    let damus_state: DamusState
    let liked: Bool
    let liked_emoji: String?
    @Binding var isOnTopHalfOfScreen: Bool
    let action: (_ emoji: String) -> Void

    // For reactions background
    @State private var showReactionsBG = 0
    @State private var rotateThumb = -45

    @State private var isReactionsVisible = false

    @State private var selectedEmoji: String = ""

    // Following four are Shaka animation properties
    let timer = Timer.publish(every: 0.10, on: .main, in: .common).autoconnect()
    @State private var shouldAnimate = false
    @State private var rotationAngle = 0.0
    @State private var amountOfAngleIncrease: Double = 0.0

    var emojis: [String] {
        damus_state.settings.emoji_reactions
    }
    
    @ViewBuilder
    func buildMaskView(for emoji: String) -> some View {
        if emoji == "🤙" {
            LINEAR_GRADIENT
                .mask(
                    Image("shaka.fill")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                )
        } else {
            Text(emoji)
        }
    }

    var body: some View {
        Group {
            if let liked_emoji {
                buildMaskView(for: liked_emoji)
                    .frame(width: 22, height: 20)
            } else {
                Image("shaka")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 22, height: 20)
                    .foregroundColor(.gray)
            }
        }
        .accessibilityLabel(NSLocalizedString("Like", comment: "Accessibility Label for Like button"))
        .rotationEffect(Angle(degrees: shouldAnimate ? rotationAngle : 0))
        .onReceive(self.timer) { _ in
            shakaAnimationLogic()
        }
        .simultaneousGesture(longPressGesture())
        .highPriorityGesture(TapGesture().onEnded {
            guard !isReactionsVisible else { return }
            withAnimation(Animation.easeOut(duration: 0.15)) {
                self.action(damus_state.settings.default_emoji_reaction)
                shouldAnimate = true
                amountOfAngleIncrease = 20.0
            }
        })
        .emojiPicker(
            isPresented: $isReactionsVisible,
            selectedEmoji: $selectedEmoji,
            arrowDirection: isOnTopHalfOfScreen ? .down : .up,
            isDismissAfterChoosing: true
        )
        .onChange(of: selectedEmoji) { newSelectedEmoji in
            self.action(newSelectedEmoji)
        }
    }

    func shakaAnimationLogic() {
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

    func longPressGesture() -> some Gesture {
        LongPressGesture(minimumDuration: 0.5).onEnded { _ in
            reactionLongPressed()
        }
    }

    // When reaction button is long pressed, it displays the multiple emojis overlay and displays the user's selected emojis with an animation
    private func reactionLongPressed() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        
        isReactionsVisible = true
    }
    
    private func emojiTapped(_ emoji: String) {
        print("Tapped emoji: \(emoji)")
        
        self.action(emoji)

        withAnimation(.easeOut(duration: 0.2)) {
            isReactionsVisible = false
        }
        
        withAnimation(Animation.easeOut(duration: 0.15)) {
            shouldAnimate = true
            amountOfAngleIncrease = 20.0
        }
    }
}


struct EventActionBar_Previews: PreviewProvider {
    static var previews: some View {
        let ds = test_damus_state
        let ev = NostrEvent(content: "hi", keypair: test_keypair)!

        let bar = ActionBarModel.empty()
        let likedbar = ActionBarModel(likes: 10, boosts: 0, zaps: 0, zap_total: 0, replies: 0, our_like: nil, our_boost: nil, our_zap: nil, our_reply: nil)
        let likedbar_ours = ActionBarModel(likes: 10, boosts: 0, zaps: 0, zap_total: 0, replies: 0, our_like: test_note, our_boost: nil, our_zap: nil, our_reply: nil)
        let maxed_bar = ActionBarModel(likes: 999, boosts: 999, zaps: 999, zap_total: 99999999, replies: 999, our_like: test_note, our_boost: test_note, our_zap: nil, our_reply: nil)
        let extra_max_bar = ActionBarModel(likes: 9999, boosts: 9999, zaps: 9999, zap_total: 99999999, replies: 9999, our_like: test_note, our_boost: test_note, our_zap: nil, our_reply: test_note)
        let mega_max_bar = ActionBarModel(likes: 9999999, boosts: 99999, zaps: 9999, zap_total: 99999999, replies: 9999999,  our_like: test_note, our_boost: test_note, our_zap: .zap(test_zap), our_reply: test_note)

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
