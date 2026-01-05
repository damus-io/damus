//
//  EventActionBar.swift
//  damus
//
//  Created by William Casarin on 2022-04-16.
//

import SwiftUI
import EmojiPicker
import EmojiKit
import SwipeActions

struct EventActionBar: View {
    let damus_state: DamusState
    let event: NostrEvent
    let generator = UIImpactFeedbackGenerator(style: .medium)
    let userProfile : ProfileModel
    let swipe_context: SwipeContext?
    let options: Options
    
    // just used for previews
    @State var show_share_sheet: Bool = false
    @State var show_share_action: Bool = false
    @State var show_repost_action: Bool = false
    @State private var showReadOnlyAlert: Bool = false

    @State private var selectedEmoji: Emoji? = nil

    private var isReadOnly: Bool {
        damus_state.keypair.privkey == nil
    }

    @ObservedObject var bar: ActionBarModel
    
    init(damus_state: DamusState, event: NostrEvent, bar: ActionBarModel? = nil, options: Options = [], swipe_context: SwipeContext? = nil) {
        self.damus_state = damus_state
        self.event = event
        _bar = ObservedObject(wrappedValue: bar ?? make_actionbar_model(ev: event.id, damus: damus_state))
        self.userProfile = ProfileModel(pubkey: event.pubkey, damus: damus_state)
        self.options = options
        self.swipe_context = swipe_context
    }
    
    @State var lnurl: String? = nil
    
    // Fetching an LNURL is expensive enough that it can cause a hitch. Use a special backgroundable function to fetch the value.
    // Fetch on `.onAppear`
    nonisolated func fetchLNURL() {
        let lnurl = try? damus_state.profiles.lookup_lnurl(event.pubkey)
        DispatchQueue.main.async {
            self.lnurl = lnurl
        }
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
    
    // MARK: Swipe action menu buttons
    
    var reply_swipe_button: some View {
        SwipeAction(systemImage: "arrowshape.turn.up.left.fill", backgroundColor: DamusColors.adaptableGrey) {
            notify(.compose(.replying_to(event)))
            self.swipe_context?.state.wrappedValue = .closed
        }
        .allowSwipeToTrigger()
        .swipeButtonStyle()
        .accessibilityLabel(NSLocalizedString("Reply", comment: "Accessibility label for reply button"))
    }
    
    var repost_swipe_button: some View {
        SwipeAction(image: "repost", backgroundColor: DamusColors.adaptableGrey) {
            if isReadOnly {
                showReadOnlyAlert = true
            } else {
                self.show_repost_action = true
            }
            self.swipe_context?.state.wrappedValue = .closed
        }
        .swipeButtonStyle()
        .accessibilityLabel(NSLocalizedString("Repost or quote this note", comment: "Accessibility label for repost/quote button"))
    }

    var like_swipe_button: some View {
        SwipeAction(image: "shaka", backgroundColor: DamusColors.adaptableGrey) {
            if isReadOnly {
                showReadOnlyAlert = true
            } else {
                Task {
                    await send_like(emoji: damus_state.settings.default_emoji_reaction)
                }
            }
            self.swipe_context?.state.wrappedValue = .closed
        }
        .swipeButtonStyle()
        .accessibilityLabel(NSLocalizedString("React with default reaction emoji", comment: "Accessibility label for react button"))
    }
    
    var share_swipe_button: some View {
        SwipeAction(image: "upload", backgroundColor: DamusColors.adaptableGrey) {
            show_share_action = true
            self.swipe_context?.state.wrappedValue = .closed
        }
        .swipeButtonStyle()
        .accessibilityLabel(NSLocalizedString("Share externally", comment: "Accessibility label for external share button"))
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
                if isReadOnly {
                    showReadOnlyAlert = true
                } else {
                    self.show_repost_action = true
                }
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
                if isReadOnly {
                    showReadOnlyAlert = true
                } else if bar.liked {
                    //notify(.delete, bar.our_like)
                } else {
                    Task { await send_like(emoji: emoji) }
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
    
    var swipe_action_menu_content: some View {
        Group {
            self.reply_swipe_button
            self.repost_swipe_button
            if show_like {
                self.like_swipe_button
            }
        }
    }
    
    var swipe_action_menu_reverse_content: some View {
        Group {
            if show_like {
                self.like_swipe_button
            }
            self.repost_swipe_button
            self.reply_swipe_button
        }
    }
    
    var action_bar_content: some View {
        let hide_items_without_activity = options.contains(.hide_items_without_activity)
        let should_hide_chat_bubble = hide_items_without_activity && bar.replies == 0
        let should_hide_repost = hide_items_without_activity && bar.boosts == 0
        let should_hide_reactions = hide_items_without_activity && bar.likes == 0
        let zap_model = self.damus_state.events.get_cache_data(self.event.id).zaps_model
        let should_hide_zap = hide_items_without_activity && zap_model.zap_total == 0
        let should_hide_share_button = hide_items_without_activity
        // Only render the bar if at least one action is visible; avoids empty overlays/dots.
        let has_any_action = (!should_hide_chat_bubble && damus_state.keypair.privkey != nil)
            || !should_hide_repost
            || (show_like && !should_hide_reactions)
            || (!should_hide_zap && self.lnurl != nil)
            || !should_hide_share_button

        return Group {
            if has_any_action {
                HStack(spacing: options.contains(.no_spread) ? 10 : 0) {
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
        }
    }
    
    var content: some View {
        if options.contains(.swipe_action_menu) {
            AnyView(self.swipe_action_menu_content)
        }
        else if options.contains(.swipe_action_menu_reverse) {
            AnyView(self.swipe_action_menu_reverse_content)
        }
        else {
            AnyView(self.action_bar_content)
        }
    }

    @State var event_relay_url_strings: [RelayURL] = []
    
    func updateEventRelayURLStrings() async {
        let newValue = await fetchEventRelayURLStrings()
        self.event_relay_url_strings = newValue
    }
    
    func fetchEventRelayURLStrings() async -> [RelayURL] {
        let relays = await damus_state.nostrNetwork.relaysForEvent(event: event)
        if !relays.isEmpty {
            return relays.prefix(Constants.MAX_SHARE_RELAYS).map { $0 }
        }

        return userProfile.getCappedRelays()
    }

    var body: some View {
        self.content
        .onAppear {
            Task.detached(priority: .background, operation: {
                await self.bar.update(damus: damus_state, evid: self.event.id)
                self.fetchLNURL()
                await self.updateEventRelayURLStrings()
            })
        }
        .sheet(isPresented: $show_share_action, onDismiss: { self.show_share_action = false }) {
            if #available(iOS 16.0, *) {
                ShareAction(event: event, bookmarks: damus_state.bookmarks, show_share: $show_share_sheet, userProfile: userProfile, isReadOnly: isReadOnly)
                    .presentationDetents([.height(300)])
                    .presentationDragIndicator(.visible)
            } else {
                ShareAction(event: event, bookmarks: damus_state.bookmarks, show_share: $show_share_sheet, userProfile: userProfile, isReadOnly: isReadOnly)
            }
        }
        .sheet(isPresented: $show_share_sheet, onDismiss: { self.show_share_sheet = false }) {
            if let url = URL(string: "https://damus.io/" + Bech32Object.encode(.nevent(NEvent(event: event, relays: event_relay_url_strings)))) {
                ShareSheet(activityItems: [url])
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
        .onReceive(handle_notify(.update_stats)) { target in
            guard target == self.event.id else { return }
            Task {
                await self.bar.update(damus: self.damus_state, evid: target)
                await self.updateEventRelayURLStrings()
            }
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
        .alert(
            NSLocalizedString("Read-Only Account", comment: "Alert title when read-only user tries to perform a write action"),
            isPresented: $showReadOnlyAlert
        ) {
            Button(NSLocalizedString("OK", comment: "Button to dismiss read-only alert")) {
                showReadOnlyAlert = false
            }
        } message: {
            Text("Log in with your private key (nsec) to react, repost, and zap.", comment: "Alert message explaining that private key is needed for write actions")
        }
    }

    func send_like(emoji: String) async {
        guard let keypair = damus_state.keypair.to_full(),
              let like_ev = await make_like_event(keypair: keypair, liked: event, content: emoji, relayURL: damus_state.nostrNetwork.relaysForEvent(event: event).first) else {
            return
        }

        self.bar.our_like = like_ev

        generator.impactOccurred()
        
        await damus_state.nostrNetwork.postbox.send(like_ev)
    }
    
    // MARK: Helper structures
    
    struct Options: OptionSet {
        let rawValue: UInt32
        
        static let no_spread = Options(rawValue: 1 << 0)
        static let hide_items_without_activity = Options(rawValue: 1 << 1)
        static let swipe_action_menu = Options(rawValue: 1 << 2)
        static let swipe_action_menu_reverse = Options(rawValue: 1 << 3)
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
    @State private var rotateThumb = -45

    @State private var isReactionsVisible = false

    @State private var selectedEmoji: Emoji?

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
        .sheet(isPresented: $isReactionsVisible) {
            NavigationView {
                EmojiPickerView(selectedEmoji: $selectedEmoji, emojiProvider: damus_state.emoji_provider)
            }.presentationDetents([.medium, .large])
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
        .onChange(of: selectedEmoji) { newSelectedEmoji in
            if let newSelectedEmoji {
                self.action(newSelectedEmoji.value)
            }
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
            
            EventActionBar(damus_state: ds, event: ev, bar: bar, options: [.no_spread])
        }
        .padding(20)
    }
}

// MARK: Helpers

fileprivate struct SwipeButtonStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(width: 50, height: 50)
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.damusAdaptableGrey2, lineWidth: 2))
    }
}

fileprivate extension View {
    func swipeButtonStyle() -> some View {
        modifier(SwipeButtonStyle())
    }
}

// MARK: Needed extensions for SwipeAction

public extension SwipeAction where Label == Image, Background == Color {
    init(
        image: String,
        backgroundColor: Color = Color.primary.opacity(0.1),
        highlightOpacity: Double = 0.5,
        action: @escaping () -> Void
    ) {
        self.init(action: action) { highlight in
            Image(image)
        } background: { highlight in
            backgroundColor
                .opacity(highlight ? highlightOpacity : 1)
        }
    }
}
