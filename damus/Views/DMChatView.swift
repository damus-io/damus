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
        .padding(.bottom, isTextFieldFocused ? 0 : tabHeight)
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
                ProfilePicView(pubkey: pubkey, size: 24, highlight: .none, profiles: damus_state.profiles, disable_animation: damus_state.settings.disable_animation)

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
                        send_message()
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

    func send_message() {
        let tags = [["p", pubkey.hex()]]
        let post_blocks = parse_post_blocks(content: dms.draft)?.blocks
        guard let content = post_blocks?.map({ pb in pb.asString }).joined(separator: "") else {
            // TODO: handle these errors somehow?
            print("error creating dm")
            return
        }

        guard let dm = NIP04.create_dm(content, to_pk: pubkey, tags: tags, keypair: damus_state.keypair) else {
            print("error creating dm")
            return
        }

        dms.draft = ""

        damus_state.nostrNetwork.postbox.send(dm)
        
        handle_incoming_dm(ev: dm, our_pubkey: damus_state.pubkey, dms: damus_state.dms, prev_events: NewEventsBits())

        end_editing()
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

