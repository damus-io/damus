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
    let userProfile : ProfileModel
    let options: Options
    
    // just used for previews
    @State var show_share_sheet: Bool = false
    @State var show_share_action: Bool = false
    @State var show_repost_action: Bool = false

    @ObservedObject var bar: ActionBarModel
    
    init(damus_state: DamusState, event: NostrEvent, bar: ActionBarModel? = nil, options: Options = []) {
        self.damus_state = damus_state
        self.event = event
        _bar = ObservedObject(wrappedValue: bar ?? make_actionbar_model(ev: event.id, damus: damus_state))
        self.userProfile = ProfileModel(pubkey: event.pubkey, damus: damus_state)
        self.options = options
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
    
    var space_if_spread: AnyView {
        if options.contains(.no_spread) {
            return AnyView(EmptyView())
        }
        else {
            return AnyView(Spacer())
        }
    }
    
    // MARK: Context menu buttons
    
    var reply_menu_button: some View {
        Button {
            notify(.compose(.replying_to(event)))
        } label: {
            Label(NSLocalizedString("Reply", comment: "Menu label for reply button"), image: "bubble2")
        }
    }
    
    var repost_menu_button: some View {
        Button {
            guard let keypair = self.damus_state.keypair.to_full(),
                  let boost = make_boost_event(keypair: keypair, boosted: self.event) else {
                return
            }

            damus_state.postbox.send(boost)
        } label: {
            Label(NSLocalizedString("Repost", comment: "Menu label for boosts button"), image: "repost")
        }
    }
    
    var quote_menu_button: some View {
        Button {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                notify(.compose(.quoting(self.event)))
            }
        } label: {
            Label(NSLocalizedString("Quote", comment: "Menu label for quote button"), systemImage: "quote.opening")
        }
    }
    
    var like_menu_button: some View {
        Button {
            send_like(emoji: "🤙")
        } label: {
            Label(NSLocalizedString("React", comment: "Button to react to a note"), image: "shaka")
        }
        .onLongPressGesture {
            print("long press")
        }
    }
    
    var zap_menu_button: AnyView {
        let zap_model = self.damus_state.events.get_cache_data(self.event.id).zaps_model
        if let lnurl = self.lnurl {
            return AnyView(NoteZapButton(damus_state: damus_state, target: ZapTarget.note(id: event.id, author: event.pubkey), lnurl: lnurl, zaps: zap_model))
        }
        else {
            return AnyView(EmptyView())
        }
    }
    
    var share_menu_button: some View {
        Button {
            show_share_action = true
        } label: {
            Label(NSLocalizedString("Share", comment: "Button to share a note"), image: "upload")
        }
    }
    
    // MARK: Bar buttons
    
    var reply_button: some View {
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
    
    var repost_button: some View {
        HStack(spacing: 4) {
            
            EventActionButton(img: "repost", col: bar.boosted ? Color.green : nil) {
                self.show_repost_action = true
            }
            .accessibilityLabel(NSLocalizedString("Reposts", comment: "Accessibility label for boosts button"))
            Text(verbatim: "\(bar.boosts > 0 ? "\(bar.boosts)" : "")")
                .font(.footnote.weight(.medium))
                .foregroundColor(bar.boosted ? Color.green : Color.gray)
        }
    }
    
    var like_button: some View {
        HStack(spacing: 4) {
            LikeButton(damus_state: damus_state, liked: bar.liked, liked_emoji: bar.our_like != nil ? to_reaction_emoji(ev: bar.our_like!) : nil) { emoji in
                if bar.liked {
                    //notify(.delete, bar.our_like)
                } else {
                    send_like(emoji: emoji)
                }
            }
            
            Text(verbatim: "\(bar.likes > 0 ? "\(bar.likes)" : "")")
                .font(.footnote.weight(.medium))
                .nip05_colorized(gradient: bar.liked)
        }
    }
    
    var share_button: some View {
        EventActionButton(img: "upload", col: Color.gray) {
            show_share_action = true
        }
        .accessibilityLabel(NSLocalizedString("Share", comment: "Button to share a note"))
    }
    
    // MARK: Main views
    
    var context_menu_content: some View {
        Group {
            self.reply_menu_button
            self.repost_menu_button
            self.quote_menu_button
            self.like_menu_button
            self.zap_menu_button
            self.share_menu_button
        }
    }
    
    var action_bar_content: some View {
        let hide_items_without_activity = options.contains(.hide_items_without_activity)
        let should_hide_chat_bubble = hide_items_without_activity && bar.replies == 0
        let should_hide_repost = hide_items_without_activity && bar.boosts == 0
        let should_hide_reactions = hide_items_without_activity && bar.likes == 0
        let zap_model = self.damus_state.events.get_cache_data(self.event.id).zaps_model
        let should_hide_zap = hide_items_without_activity && zap_model.zap_total > 0
        let should_hide_share_button = hide_items_without_activity

        return HStack(spacing: options.contains(.no_spread) ? 10 : 0) {
            if damus_state.keypair.privkey != nil && !should_hide_chat_bubble {
                self.reply_button
            }
            
            if !should_hide_repost {
                self.space_if_spread
                self.repost_button
            }
                
            if show_like && !should_hide_reactions {
                self.space_if_spread
                self.like_button
            }
                
            if let lnurl = self.lnurl, !should_hide_zap {
                self.space_if_spread
                NoteZapButton(damus_state: damus_state, target: ZapTarget.note(id: event.id, author: event.pubkey), lnurl: lnurl, zaps: zap_model)
            }
            
            if !should_hide_share_button {
                self.space_if_spread
                self.share_button
            }
        }
    }
    
    var content: some View {
        if options.contains(.context_menu) {
            AnyView(self.context_menu_content)
        }
        else {
            AnyView(self.action_bar_content)
        }
    }
    
    var body: some View {
        self.content
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
    
    // MARK: Helper structures
    
    struct Options: OptionSet {
        let rawValue: UInt32
        
        static let no_spread = Options(rawValue: 1 << 0)
        static let hide_items_without_activity = Options(rawValue: 1 << 1)
        static let context_menu = Options(rawValue: 1 << 2)
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
    let action: (_ emoji: String) -> Void

    // For reactions background
    @State private var showReactionsBG = 0
    @State private var showEmojis: [Int] = []
    @State private var rotateThumb = -45

    @State private var isReactionsVisible = false

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
        .overlay(reactionsOverlay())
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

    func reactionsOverlay() -> some View {
        Group {
            if isReactionsVisible {
                ZStack {
                    RoundedRectangle(cornerRadius: 20)
                        .frame(width: calculateOverlayWidth(), height: 50)
                        .foregroundColor(DamusColors.black)
                        .scaleEffect(Double(showReactionsBG), anchor: .topTrailing)
                        .animation(
                            .interpolatingSpring(stiffness: 170, damping: 15).delay(0.05),
                            value: showReactionsBG
                        )
                        .overlay(
                            Rectangle()
                                .foregroundColor(Color.white.opacity(0.2))
                                .frame(width: calculateOverlayWidth(), height: 50)
                                .clipShape(
                                    RoundedRectangle(cornerRadius: 20)
                                )
                        )
                        .overlay(Reactions(emojis: self.emojis, emojiTapped: self.emojiTapped, close: closeReactions))
                }
                .offset(y: -40)
                .onTapGesture {
                    withAnimation(.easeOut(duration: 0.2)) {
                        isReactionsVisible = false
                        showReactionsBG = 0
                    }
                    showEmojis = []
                }
            } else {
                EmptyView()
            }
        }
    }
    
    func calculateOverlayWidth() -> CGFloat {
        let maxWidth: CGFloat = 250
        let numberOfEmojis = emojis.count
        let minimumWidth: CGFloat = 75
        
        if numberOfEmojis > 0 {
            let emojiWidth: CGFloat = 25
            let padding: CGFloat = 15
            let buttonWidth: CGFloat = 18
            let buttonPadding: CGFloat = 20
            
            let totalWidth = CGFloat(numberOfEmojis) * (emojiWidth + padding) + buttonWidth + buttonPadding
            return min(maxWidth, max(minimumWidth, totalWidth))
        } else {
            return minimumWidth
        }
    }
    
    func closeReactions() {
        isReactionsVisible = false
        showReactionsBG = 0
        return
    }
    
    struct Reactions: View {
        let emojis: [String]
        @State private var showEmojis: [Int] = []
        let emojiTapped: (String) -> Void
        let close: () -> Void
        
        var body: some View {
            HStack {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 15) {
                        ForEach(emojis, id: \.self) { emoji in
                            if let index = emojis.firstIndex(of: emoji) {
                                let scale = index < showEmojis.count ? showEmojis[index] : 0
                                Text(emoji)
                                    .font(.system(size: 25))
                                    .scaleEffect(Double(scale))
                                    .onTapGesture {
                                        emojiTapped(emoji)
                                    }
                            }
                        }
                    }
                    .padding(.leading, 10)
                }
                Button(action: {
                    withAnimation(.easeOut(duration: 0.2)) {
                        self.close()
                    }
                    showEmojis = []
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.gray)
                }
                .padding(.trailing, 7.5)
            }
        }
    }

    // When reaction button is long pressed, it displays the multiple emojis overlay and displays the user's selected emojis with an animation
    private func reactionLongPressed() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        showEmojis = Array(repeating: 0, count: emojis.count) // Initialize the showEmojis array
        
        for (index, _) in emojis.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1 * Double(index)) {
                withAnimation(.interpolatingSpring(stiffness: 170, damping: 8)) {
                    if index < showEmojis.count {
                        showEmojis[index] = 1
                    }
                }
            }
        }
        
        isReactionsVisible = true
        showReactionsBG = 1
    }
    
    private func emojiTapped(_ emoji: String) {
        print("Tapped emoji: \(emoji)")
        
        self.action(emoji)

        withAnimation(.easeOut(duration: 0.2)) {
            isReactionsVisible = false
            showReactionsBG = 0
        }
        showEmojis = []
        
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
            
            EventActionBar(damus_state: ds, event: ev, bar: bar, options: [.no_spread])
        }
        .padding(20)
    }
}
