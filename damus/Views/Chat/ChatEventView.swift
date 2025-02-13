//
//  ChatView.swift
//  damus
//
//  Created by William Casarin on 2022-04-19.
//

import SwiftUI
import EmojiKit
import EmojiPicker
import SwipeActions

fileprivate let CORNER_RADIUS: CGFloat = 10

struct ChatEventView: View {
    // MARK: Parameters
    let event: NostrEvent
    let selected_event: NostrEvent
    let prev_ev: NostrEvent?
    let next_ev: NostrEvent?
    let damus_state: DamusState
    var thread: ThreadModel
    let scroll_to_event: ((_ id: NoteId) -> Void)?
    let focus_event: (() -> Void)?
    let highlight_bubble: Bool
    
    // MARK: long-press reaction control objects
    /// Whether the user is actively pressing the view
    @State var is_pressing = false
    @State var popover_state: PopoverState = .closed {
        didSet {
            let generator = UIImpactFeedbackGenerator(style: popover_state.some_sheet_open() ? .heavy : .light)
            generator.impactOccurred()
        }
    }
    @State var selected_emoji: Emoji?

    @State private var isOnTopHalfOfScreen: Bool = false
    @ObservedObject var bar: ActionBarModel
    @Environment(\.swipeViewGroupSelection) var swipeViewGroupSelection
    
    enum PopoverState: String {
        case closed
        case open_emoji_selector
        case open_zap_sheet

        func some_sheet_open() -> Bool {
            return self == .open_zap_sheet || self == .open_emoji_selector
        }
    }

    var just_started: Bool {
        return prev_ev == nil || prev_ev!.pubkey != event.pubkey
    }

    func next_replies_to_this() -> Bool {
        guard let next = next_ev else {
            return false
        }

        return damus_state.events.replies.lookup(next.id) != nil
    }

    func is_reply_to_prev(ref_id: NoteId) -> Bool {
        guard let prev = prev_ev else {
            return true
        }

        if let rep = damus_state.events.replies.lookup(event.id) {
            return rep.contains(prev.id)
        }

        return false
    }

    var disable_animation: Bool {
        self.damus_state.settings.disable_animation
    }

    var reply_quote_options: EventViewOptions {
        return [.no_previews, .no_action_bar, .truncate_content_very_short, .no_show_more, .no_translate, .no_media]
    }
    
    var profile_picture_view: some View {
        VStack {
            ProfilePicView(pubkey: event.pubkey, size: 32, highlight: .none, profiles: damus_state.profiles, disable_animation: disable_animation)
                .onTapGesture {
                    show_profile_action_sheet_if_enabled(damus_state: damus_state, pubkey: event.pubkey)
                }
        }
        .frame(maxWidth: 32)
    }
    
    var by_other_user: Bool {
        return event.pubkey != damus_state.pubkey
    }

    var is_ours: Bool { return !by_other_user }

    // MARK: Zapping properties

    var lnurl: String? {
        damus_state.profiles.lookup_with_timestamp(event.pubkey)?.map({ pr in
            pr?.lnurl
        }).value
    }
    var zap_target: ZapTarget {
        ZapTarget.note(id: event.id, author: event.pubkey)
    }

    // MARK: Views

    var event_bubble: some View {
        ChatBubble(
            direction: is_ours ? .right : .left,
            stroke_content: Color.accentColor.opacity(highlight_bubble ? 1 : 0),
            stroke_style: .init(lineWidth: 4),
            background_style: by_other_user ? DamusColors.adaptableGrey : DamusColors.adaptablePurpleBackground
        ) {
            VStack(alignment: .leading, spacing: 4) {
                if by_other_user {
                    HStack {
                        ProfileName(pubkey: event.pubkey, damus: damus_state)
                            .onTapGesture {
                                show_profile_action_sheet_if_enabled(damus_state: damus_state, pubkey: event.pubkey)
                            }
                            .lineLimit(1)
                        Text(verbatim: "\(format_relative_time(event.created_at))")
                            .foregroundColor(.gray)
                    }
                }
                
                if let replying_to = event.direct_replies(),
                   replying_to != selected_event.id {
                    ReplyQuoteView(keypair: damus_state.keypair, quoter: event, event_id: replying_to, state: damus_state, thread: thread, options: reply_quote_options)
                        .background(is_ours ? DamusColors.adaptablePurpleBackground2 : DamusColors.adaptableGrey2)
                        .foregroundColor(is_ours ? Color.damusAdaptablePurpleForeground : Color.damusAdaptableBlack)
                        .cornerRadius(5)
                        .onTapGesture {
                            self.scroll_to_event?(replying_to)
                        }
                }
                
                let blur_images = should_blur_images(settings: damus_state.settings, contacts: damus_state.contacts, ev: event, our_pubkey: damus_state.pubkey)
                NoteContentView(damus_state: damus_state, event: event, blur_images: blur_images, size: .normal, options: [.truncate_content])
                    .padding(2)
                if let mention = first_eref_mention(ndb: damus_state.ndb, ev: event, keypair: damus_state.keypair) {
                    MentionView(damus_state: damus_state, mention: mention)
                        .background(DamusColors.adaptableWhite)
                        .clipShape(RoundedRectangle(cornerSize: CGSize(width: 10, height: 10)))
                }
            }
            .frame(minWidth: 5, alignment: is_ours ? .trailing : .leading)
            .padding(10)
        }
        .tint(Color.accentColor)
        .overlay(
            ZStack(alignment: is_ours ? .bottomLeading : .bottomTrailing) {
                VStack {
                    Spacer()
                    self.action_bar
                        .padding(.horizontal, 5)
                }
            }
        )
        .onTapGesture {
            if popover_state == .closed {
                focus_event?()
            }
            else {
                popover_state = .closed
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
            }
        }
    }
    
    var event_bubble_with_long_press_interaction: some View {
        ZStack(alignment: is_ours ? .bottomLeading : .bottomTrailing) {
            self.event_bubble
                .sheet(isPresented: Binding(get: { popover_state == .open_emoji_selector }, set: { new_state in
                    withAnimation(new_state == true ? .easeIn(duration: 0.5) : .easeOut(duration: 0.1)) {
                        popover_state = new_state == true ? .open_emoji_selector : .closed
                    }
                })) {
                    NavigationView {
                        EmojiPickerView(selectedEmoji: $selected_emoji, emojiProvider: damus_state.emoji_provider)
                    }.presentationDetents([.medium, .large])
                }
                .sheet(isPresented: Binding(get: { popover_state == .open_zap_sheet }, set: { new_state in
                    withAnimation(new_state == true ? .easeIn(duration: 0.5) : .easeOut(duration: 0.1)) {
                        popover_state = new_state == true ? .open_zap_sheet : .closed
                    }
                })) {
                    ZapSheetViewIfPossible(damus_state: damus_state, target: zap_target, lnurl: lnurl)
                        .presentationDetents([.medium, .large])
                }
                .onChange(of: selected_emoji) { newSelectedEmoji in
                    if let newSelectedEmoji {
                        send_like(emoji: newSelectedEmoji.value)
                        popover_state = .closed
                    }
                }
        }
        .scaleEffect(self.popover_state.some_sheet_open() ? 1.08 : is_pressing ? 1.02 : 1)
        .shadow(color: (is_pressing || self.popover_state.some_sheet_open()) ? .black.opacity(0.1) : .black.opacity(0.3), radius: (is_pressing || self.popover_state.some_sheet_open()) ? 8 : 0, y: (is_pressing || self.popover_state.some_sheet_open()) ? 15 : 0)
        .onLongPressGesture(minimumDuration: 0.5, maximumDistance: 10, perform: {
            withAnimation(.bouncy(duration: 0.2, extraBounce: 0.35)) {
                let should_show_zap_sheet = !damus_state.settings.nozaps && damus_state.settings.onlyzaps_mode
                popover_state = should_show_zap_sheet ? .open_zap_sheet : .open_emoji_selector
            }
        }, onPressingChanged: { is_pressing in
            withAnimation(is_pressing ? .easeIn(duration: 0.5) : .easeOut(duration: 0.1)) {
                self.is_pressing = is_pressing
            }
        })
        .onChange(of: swipeViewGroupSelection.wrappedValue) { newValue in
            self.is_pressing = false
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

        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        
        damus_state.nostrNetwork.postbox.send(like_ev)
    }
    
    var action_bar: some View {
        return Group {
            if !bar.is_empty {
                HStack {
                    if by_other_user {
                        Spacer()
                    }
                    EventActionBar(damus_state: damus_state, event: event, bar: bar, options: [.no_spread, .hide_items_without_activity])
                        .padding(10)
                        .background(DamusColors.adaptableLighterGrey)
                        .disabled(true)
                        .cornerRadius(100)
                        .overlay(RoundedRectangle(cornerSize: CGSize(width: 100, height: 100)).stroke(DamusColors.adaptableWhite, lineWidth: 1))
                        .shadow(color: Color.black.opacity(0.05),radius: 3, y: 3)
                        .scaleEffect(0.7, anchor: is_ours ? .leading : .trailing)
                    if !by_other_user {
                        Spacer()
                    }
                }
                .padding(.vertical, -20)
            }
        }
    }
    
    var event_bubble_with_long_press_and_swipe_interactions: some View {
        Group {
            SwipeView {
                self.event_bubble_with_long_press_interaction
            } leadingActions: { context in
                if !is_ours {
                    EventActionBar(
                        damus_state: damus_state,
                        event: event,
                        bar: bar,
                        options: is_ours ? [.swipe_action_menu_reverse] : [.swipe_action_menu],
                        swipe_context: context
                    )
                }
            } trailingActions: { context in
                if is_ours {
                    EventActionBar(
                        damus_state: damus_state,
                        event: event,
                        bar: bar,
                        options: is_ours ? [.swipe_action_menu_reverse] : [.swipe_action_menu],
                        swipe_context: context
                    )
                }
            }
            .swipeSpacing(-20)
            .swipeActionsStyle(.mask)
            .swipeMinimumDistance(40)
            .swipeDragGesturePriority(.normal)
        }
    }
    
    var content: some View {
        return VStack {
            HStack(alignment: .bottom, spacing: 4) {
                if by_other_user {
                    self.profile_picture_view
                }
                else {
                    Spacer()
                }
                
                self.event_bubble_with_long_press_and_swipe_interactions
                
                if !by_other_user {
                    self.profile_picture_view
                }
                else {
                    Spacer()
                }
            }
            .contentShape(Rectangle())
            .id(event.id)
            .padding([.bottom], bar.is_empty ? 6 : 16)
        }
    }

    var body: some View {
        if [.boost, .zap, .longform].contains(where: { event.known_kind == $0 }) {
            EmptyView()
        } else {
            self.content
        }
    }
}

extension Notification.Name {
    static var toggle_thread_view: Notification.Name {
        return Notification.Name("convert_to_thread")
    }
}

#Preview {
    let bar = make_actionbar_model(ev: test_note.id, damus: test_damus_state)
    return ChatEventView(event: test_note, selected_event: test_note, prev_ev: nil, next_ev: nil, damus_state: test_damus_state, thread: ThreadModel(event: test_note, damus_state: test_damus_state), scroll_to_event: nil, focus_event: nil, highlight_bubble: false, bar: bar)
}

#Preview {
    let bar = make_actionbar_model(ev: test_note.id, damus: test_damus_state)
    return ChatEventView(event: test_short_note, selected_event: test_note, prev_ev: nil, next_ev: nil, damus_state: test_damus_state, thread: ThreadModel(event: test_note, damus_state: test_damus_state), scroll_to_event: nil, focus_event: nil, highlight_bubble: false, bar: bar)
}

#Preview {
    let bar = make_actionbar_model(ev: test_note.id, damus: test_damus_state)
    return ChatEventView(event: test_short_note, selected_event: test_note, prev_ev: nil, next_ev: nil, damus_state: test_damus_state, thread: ThreadModel(event: test_note, damus_state: test_damus_state), scroll_to_event: nil, focus_event: nil, highlight_bubble: true, bar: bar)
}

#Preview {
    let bar = make_actionbar_model(ev: test_note.id, damus: test_damus_state)
    return ChatEventView(event: test_super_short_note, selected_event: test_note, prev_ev: nil, next_ev: nil, damus_state: test_damus_state, thread: ThreadModel(event: test_note, damus_state: test_damus_state), scroll_to_event: nil, focus_event: nil, highlight_bubble: false, bar: bar)
}
