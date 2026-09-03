//
//  DMChatView.swift
//  damus
//
//  Created by William Casarin on 2022-06-30.
//

import SwiftUI
import Combine

struct DMChatView: View, KeyboardReadable {
    let damus_state: DamusState
    @FocusState private var isTextFieldFocused: Bool
    @ObservedObject var dms: DirectMessageModel
    
    var pubkey: Pubkey {
        dms.pubkey
    }
    
    var Messages: some View {
        ScrollViewReader { scroller in
            ScrollView {
                LazyVStack(alignment: .leading) {
                    ForEach(Array(zip(dms.events, dms.events.indices)).filter { should_show_event(state: damus_state, ev: $0.0)}, id: \.0.id) { (ev, ind) in
                        DMView(event: dms.events[ind], damus_state: damus_state)
                            .contextMenu{MenuItems(damus_state: damus_state, event: ev, target_pubkey: ev.pubkey, profileModel: ProfileModel(pubkey: ev.pubkey, damus: damus_state))}
                    }
                    EndBlock(height: 1)
                }
                .padding(.horizontal)

            }
            .dismissKeyboardOnTap()
            .onAppear {
                scroll_to_end(scroller)
            }.onChange(of: dms.events.count) { _ in
                scroll_to_end(scroller, animated: true)
            }
            
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
    
    func scroll_to_end(_ scroller: ScrollViewProxy, animated: Bool = false) {
        if animated {
            withAnimation {
                scroller.scrollTo("endblock")
            }
        } else {
            scroller.scrollTo("endblock")
        }
    }

    var Header: some View {
        return NavigationLink(value: Route.ProfileByKey(pubkey: pubkey)) {
            HStack {
                ProfilePicView(pubkey: pubkey, size: 24, highlight: .none, profiles: damus_state.profiles, disable_animation: damus_state.settings.disable_animation, damusState: damus_state)

                ProfileName(pubkey: pubkey, damus: damus_state)
            }
        }
        .buttonStyle(PlainButtonStyle())
    }

    var InputField: some View {
        TextEditor(text: $dms.draft)
            .textEditorBackground {
                InputBackground()
            }
            .focused($isTextFieldFocused)
            .cornerRadius(8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(style: .init(lineWidth: 2))
                    .foregroundColor(.secondary.opacity(0.2))
            )
            .padding(16)
            .foregroundColor(Color.primary)
            .frame(minHeight: 70, maxHeight: 150, alignment: .bottom)
            .fixedSize(horizontal: false, vertical: true)
    }

    @Environment(\.colorScheme) var colorScheme

    func InputBackground() -> Color {
        if colorScheme == .light {
            return Color.init(.sRGB, red: 0.9, green: 0.9, blue: 0.9, opacity: 1.0)
        } else {
            return Color.init(.sRGB, red: 0.1, green: 0.1, blue: 0.1, opacity: 1.0)
        }
    }

    var Footer: some View {
    
        HStack(spacing: 0) {
            InputField

            if !dms.draft.isEmpty {
                Button(
                    role: .none,
                    action: {
                        Task { await send_message() }
                    }
                ) {
                    Label("", image: "send")
                        .font(.title)
                }
            }
        }

        /*
        Text(dms.draft).opacity(0).padding(.all, 8)
            .fixedSize(horizontal: false, vertical: true)
            .frame(minHeight: 70, maxHeight: 150, alignment: .bottom)
         */
    }

    /// Sends the draft as a NIP-17 private direct message.
    ///
    /// What goes on the relay is a pair of NIP-59 giftwraps, never the message. The copy addressed to
    /// us is also handed straight to the local database, which is what makes the message appear in
    /// this view: nostrdb peels it into a kind-14 rumor and the subscription the DM list already
    /// reads delivers it, through the very same path an inbound message arrives by. That is
    /// deliberately *not* an optimistic insert of a locally-built event — going through the real read
    /// path means a sent message that shows up here is a message our own reader could open, so a
    /// wrap we somehow built wrong fails visibly here instead of quietly becoming unreadable history.
    ///
    /// It also means we do not have to wait for the relay to echo our own wrap back to us, which is
    /// the only other way our sent messages would ever reach the database.
    ///
    /// The two wraps are published to different relays — each addressee's own NIP-17 DM inbox relays
    /// (kind 10050), which is the only place either of us is guaranteed to look for a message meant
    /// for us. See ``NostrNetworkManager/publishGiftWrap(_:to:)``.
    func send_message() async {
        guard let post_blocks = parse_post_blocks(content: dms.draft)?.blocks else {
            return
        }
        let content = post_blocks.map({ pb in pb.asString }).joined(separator: "")

        // The seal has to be signed by us, so a pubkey-only login cannot send.
        guard let keypair = damus_state.keypair.to_full() else {
            Log.error("Cannot send a NIP-17 DM without a private key", for: .networking)
            return
        }

        let dm: NIP17.DirectMessage
        do {
            dm = try NIP17.createDirectMessage(content, to: pubkey, keypair: keypair)
        }
        catch {
            Log.error("Failed to build a NIP-17 DM: %s", for: .networking, error.localizedDescription)
            return
        }

        dms.draft = ""

        do { try damus_state.ndb.add(event: dm.giftWrapToSelf) }
        catch {
            // The message is on its way regardless; it will show up once a relay echoes our own wrap
            // back to the giftwrap subscription. Losing the local copy only costs us the immediate echo.
            Log.error("Failed to ingest our own NIP-17 giftwrap locally: %s", for: .ndb, error.localizedDescription)
        }

        end_editing()

        // Each wrap goes to its own addressee's DM inbox relays, which is what makes a NIP-17 message
        // reachable rather than merely valid: theirs to the relays they told the world they read DMs
        // from, ours to the ones we read. Sending both to our own write relays — what phase 6 did —
        // lands their copy somewhere they have no reason to look.
        //
        // Our own inbox goes first, and only then theirs: this half is a local read, while looking up
        // their kind-10050 may have to go ask the network for it, and the message should not sit
        // unsent on our side for the length of someone else's relay round trip.
        let userRelayList = damus_state.nostrNetwork.userRelayList
        let ourInboxRelays = userRelayList.ourBestEffortDMInboxRelays()
        await damus_state.nostrNetwork.publishGiftWrap(dm.giftWrapToSelf, to: ourInboxRelays)

        if let wrapToReceiver = dm.giftWrapToReceiver {
            // `nil` when they have published no kind-10050, which is still the common case; the publish
            // path falls back to our own write relays for it.
            let theirInboxRelays = await userRelayList.fetchDMInboxRelays(for: pubkey)
            await damus_state.nostrNetwork.publishGiftWrap(wrapToReceiver, to: theirInboxRelays)
        }
    }

    var body: some View {
        ZStack {
            Messages

            Text("Send a message to start the conversation...", comment: "Text prompt for user to send a message to the other user.")
                .lineLimit(nil)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .opacity(((dms.events.count == 0) ? 1.0 : 0.0))
                .foregroundColor(.gray)
        }
        .navigationTitle(NSLocalizedString("DMs", comment: "Navigation title for DMs view, where DM is the English abbreviation for Direct Message."))
        .toolbar { Header }
        .onDisappear {
            if dms.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                dms.draft = ""
            }
        }
    }
}

struct DMChatView_Previews: PreviewProvider {
    static var previews: some View {
        let ev = NostrEvent(content: "hi", keypair: test_keypair, kind: 1, tags: [])!

        let model = DirectMessageModel(events: [ev], our_pubkey: test_pubkey, pubkey: test_pubkey)

        DMChatView(damus_state: test_damus_state, dms: model)
    }
}

extension View {
/// Layers the given views behind this ``TextEditor``.
    func textEditorBackground<V>(@ViewBuilder _ content: () -> V) -> some View where V : View {
        self
            .onAppear {
                UITextView.appearance().backgroundColor = .clear
            }
            .background(content())
    }
}

