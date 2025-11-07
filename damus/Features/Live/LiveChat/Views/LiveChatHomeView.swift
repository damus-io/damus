//
//  LiveChatHomeView.swift
//  damus
//
//  Created by eric on 8/7/25.
//

import SwiftUI

struct LiveChatHomeView: View, KeyboardReadable {
    let state: DamusState
    let event: LiveEvent
    @StateObject var model: LiveChatModel
    @State private var chat_message = ""
    @FocusState private var isTextFieldFocused: Bool
    @Environment(\.colorScheme) var colorScheme

    func content_filter(_ fstate: FilterState) -> ((NostrEvent) -> Bool) {
        var filters = ContentFilters.defaults(damus_state: state)
        filters.append(fstate.filter)
        return ContentFilters(filters: filters).filter
    }

    var Footer: some View {
        HStack(spacing: 0) {
            ChatInput

            Button(
                role: .none,
                action: {
                    Task { await send_chat() }
                }
            ) {
                Label("", image: "send")
                    .font(.title)
            }
            .disabled(chat_message.isEmpty)
        }
        .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: 10)
        }
    }


    func send_chat() async {
        guard
            let keypair = state.keypair.to_full(),
            let liveChat = make_live_chat_event(keypair: keypair, content: chat_message, root: event.event.pubkey.hex(), dtag: event.uuid ?? "", relayURL: nil)
        else {
            return
        }
        await state.nostrNetwork.postbox.send(liveChat)
        chat_message = ""
        end_editing()
    }

    var ChatInput: some View {
        HStack{
            TextField(NSLocalizedString("Chat", comment: "Placeholder text to prompt entry of chat message."), text: $chat_message)
                .autocorrectionDisabled(true)
                .textInputAutocapitalization(.never)
                .focused($isTextFieldFocused)
        }
        .padding(10)
        .background(.secondary.opacity(0.2))
        .cornerRadius(20)
        .padding(.horizontal, 15)
    }

    func scroll_to_end(_ scroller: ScrollViewProxy, animated: Bool = false) {
        if animated {
            withAnimation {
                scroller.scrollTo("endblock")
            }
        } else {
            scroller.scrollTo("endblock")
        }
    }

    var Chat: some View {
        ScrollViewReader { scroller in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    let events = model.events.events
                    ForEach(Array(zip(events, events.indices).reversed()).filter { should_show_event(state: state, ev: $0.0)}, id: \.0.id) { (ev, ind) in
                        TextEvent(damus: state, event: ev, pubkey: ev.pubkey, options: .live_chat)
                    }
                    EndBlock(height: 1)
                }
            }
            .dismissKeyboardOnTap()
            .onAppear {
                scroll_to_end(scroller)
            }.onChange(of: model.events.events.count) { _ in
                scroll_to_end(scroller, animated: true)
            }
            .padding(.top, 5)

            Footer
                .onReceive(keyboardPublisher) { visible in
                    guard visible else {
                        return
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        scroll_to_end(scroller, animated: true)
                    }
                }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Live Chat")
                    .fontWeight(.bold)
                    .padding(5)

                LiveStreamViewers(state: state, currentParticipants: event.currentParticipants ?? 0, preview: false)
            }

            Divider()

            Chat
        }
        .onReceive(handle_notify(.new_mutes)) { _ in
            self.model.filter_muted()
        }
        .onAppear {
            model.subscribe()
        }
        .onDisappear {
            model.unsubscribe()
        }

    }
}
