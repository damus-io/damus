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
    @ObservedObject var dms: DirectMessageModel
    @State var showPrivateKeyWarning: Bool = false
    
    var pubkey: String {
        dms.pubkey
    }
    
    var Messages: some View {
        ScrollViewReader { scroller in
            ScrollView {
                LazyVStack(alignment: .leading) {
                    ForEach(Array(zip(dms.events, dms.events.indices)), id: \.0.id) { (ev, ind) in
                        DMView(event: dms.events[ind], damus_state: damus_state)
                            .contextMenu{MenuItems(event: ev, keypair: damus_state.keypair, target_pubkey: ev.pubkey, bookmarks: damus_state.bookmarks, muted_threads: damus_state.muted_threads)}
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
        let profile = damus_state.profiles.lookup(id: pubkey)
        let profile_page = ProfileView(damus_state: damus_state, pubkey: pubkey)
        return NavigationLink(destination: profile_page) {
            HStack {
                ProfilePicView(pubkey: pubkey, size: 24, highlight: .none, profiles: damus_state.profiles, disable_animation: damus_state.settings.disable_animation)

                ProfileName(pubkey: pubkey, profile: profile, damus: damus_state)
            }
        }
        .buttonStyle(PlainButtonStyle())
    }

    var InputField: some View {
        TextEditor(text: $dms.draft)
            .textEditorBackground {
                InputBackground()
            }
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
                        showPrivateKeyWarning = contentContainsPrivateKey(dms.draft)

                        if !showPrivateKeyWarning {
                            send_message()
                        }
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
        let tags = [["p", pubkey]]
        let post_blocks = parse_post_blocks(content: dms.draft)
        let post_tags = make_post_tags(post_blocks: post_blocks, tags: tags, silent_mentions: true)
        let content = render_blocks(blocks: post_tags.blocks)
        
        guard let dm = create_dm(content, to_pk: pubkey, tags: post_tags.tags, keypair: damus_state.keypair) else {
            print("error creating dm")
            return
        }

        dms.draft = ""

        damus_state.postbox.send(dm)
        
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
        .alert(NSLocalizedString("Note contains \"nsec1\" private key. Are you sure?", comment: "Alert user that they might be attempting to paste a private key and ask them to confirm."), isPresented: $showPrivateKeyWarning, actions: {
            Button(NSLocalizedString("No", comment: "Button to cancel out of posting a note after being alerted that it looks like they might be posting a private key."), role: .cancel) {
                showPrivateKeyWarning = false
            }
            Button(NSLocalizedString("Yes, Post with Private Key", comment: "Button to proceed with posting a note even though it looks like they might be posting a private key."), role: .destructive) {
                send_message()
            }
        })
    }
}

struct DMChatView_Previews: PreviewProvider {
    static var previews: some View {
        let ev = NostrEvent(content: "hi", pubkey: "pubkey", kind: 1, tags: [])

        let model = DirectMessageModel(events: [ev], our_pubkey: "pubkey", pubkey: "the_pk")

        DMChatView(damus_state: test_damus_state(), dms: model)
    }
}

enum EncEncoding {
    case base64
    case bech32
}

func encrypt_message(message: String, privkey: String, to_pk: String, encoding: EncEncoding = .base64) -> String? {
    let iv = random_bytes(count: 16).bytes
    guard let shared_sec = get_shared_secret(privkey: privkey, pubkey: to_pk) else {
        return nil
    }
    let utf8_message = Data(message.utf8).bytes
    guard let enc_message = aes_encrypt(data: utf8_message, iv: iv, shared_sec: shared_sec) else {
        return nil
    }
    
    switch encoding {
    case .base64:
        return encode_dm_base64(content: enc_message.bytes, iv: iv)
    case .bech32:
        return encode_dm_bech32(content: enc_message.bytes, iv: iv)
    }
    
}

func create_encrypted_event(_ message: String, to_pk: String, tags: [[String]], keypair: FullKeypair, created_at: Int64, kind: Int) -> NostrEvent? {
    
    let privkey = keypair.privkey
    
    guard let enc_content = encrypt_message(message: message, privkey: privkey, to_pk: to_pk) else {
        return nil
    }
    
    let ev = NostrEvent(content: enc_content, pubkey: keypair.pubkey, kind: kind, tags: tags, createdAt: created_at)
    
    ev.calculate_id()
    ev.sign(privkey: privkey)
    return ev
}

func create_dm(_ message: String, to_pk: String, tags: [[String]], keypair: Keypair, created_at: Int64? = nil) -> NostrEvent?
{
    let created = created_at ?? Int64(Date().timeIntervalSince1970)
    
    guard let keypair = keypair.to_full() else {
        return nil
    }
    
    return create_encrypted_event(message, to_pk: to_pk, tags: tags, keypair: keypair, created_at: created, kind: 4)
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

