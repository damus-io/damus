//
//  DMChatView.swift
//  damus
//
//  Created by William Casarin on 2022-06-30.
//

import SwiftUI

struct DMChatView: View {
    let damus_state: DamusState
    let pubkey: String
    @EnvironmentObject var dms: DirectMessageModel
    @State var message: String = ""

    var Messages: some View {
        ScrollViewReader { scroller in
            ScrollView {
                VStack(alignment: .leading) {
                    ForEach(Array(zip(dms.events, dms.events.indices)), id: \.0.id) { (ev, ind) in
                        DMView(event: dms.events[ind], damus_state: damus_state)
                            .event_context_menu(ev, privkey: damus_state.keypair.privkey)
                    }
                    EndBlock(height: 80)
                }
                .padding(.horizontal)
            }
            .onAppear {
                scroller.scrollTo("endblock")
            }.onChange(of: dms.events.count) { _ in
                withAnimation {
                    scroller.scrollTo("endblock")
                }
            }
        }
    }

    var Header: some View {
        let profile = damus_state.profiles.lookup(id: pubkey)
        let pmodel = ProfileModel(pubkey: pubkey, damus: damus_state)
        let fmodel = FollowersModel(damus_state: damus_state, target: pubkey)
        let profile_page = ProfileView(damus_state: damus_state, profile: pmodel, followers: fmodel)
        return NavigationLink(destination: profile_page) {
            HStack {
                ProfilePicView(pubkey: pubkey, size: 24, highlight: .none, profiles: damus_state.profiles)

                ProfileName(pubkey: pubkey, profile: profile, damus: damus_state, show_friend_confirmed: true)
            }
        }
        .buttonStyle(PlainButtonStyle())
    }

    var InputField: some View {
        TextEditor(text: $message)
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
    }

    @Environment(\.colorScheme) var colorScheme

    func InputBackground() -> Color {
        if colorScheme == .light {
            return Color.init(.sRGB, red: 0.9, green: 0.9, blue: 0.9, opacity: 1.0)
        } else {
            return Color.init(.sRGB, red: 0.1, green: 0.1, blue: 0.1, opacity: 1.0)
        }
    }

    func BackgroundColor() -> some View {
        if colorScheme == .dark {
            return Color.black.opacity(0.9)
        } else {
            return Color.white.opacity(0.9)
        }
    }

    var Footer: some View {
        ZStack {
            BackgroundColor()
            
            HStack(spacing: 0) {
                InputField

                if !message.isEmpty {
                    Button(role: .none, action: send_message) {
                        Label("", systemImage: "arrow.right.circle")
                            .font(.title)
                    }
                }
            }
        }
        .frame(height: 50 + 20 * CGFloat(text_lines))
    }

    var text_lines: Int {
        var lines = 1
        for c in message {
            if lines > 4 {
                return lines
            }
            if c.isNewline {
                lines += 1
            }
        }

        return lines
    }

    func send_message() {
        let tags = [["p", pubkey]]
        let post_blocks = parse_post_blocks(content: message)
        let post_tags = make_post_tags(post_blocks: post_blocks, tags: tags)
        let content = render_blocks(blocks: post_tags.blocks)
        
        guard let dm = create_dm(content, to_pk: pubkey, tags: post_tags.tags, keypair: damus_state.keypair) else {
            print("error creating dm")
            return
        }

        message = ""

        damus_state.pool.send(.event(dm))
        end_editing()
    }

    var body: some View {
        ZStack {
            Messages
                .dismissKeyboardOnTap()

            VStack {
                Spacer()

                Footer
            }
            Text("Send a message to start the conversation...")
            .lineLimit(nil)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 40)
            .opacity(((dms.events.count == 0) ? 1.0 : 0.0))
            .foregroundColor(.gray)
        }
        .navigationTitle("DM")
        .toolbar { Header }
    }
}

struct DMChatView_Previews: PreviewProvider {
    static var previews: some View {
        let ev = NostrEvent(content: "hi", pubkey: "pubkey", kind: 1, tags: [])

        let model = DirectMessageModel(events: [ev])

        DMChatView(damus_state: test_damus_state(), pubkey: "pubkey")
            .environmentObject(model)
    }
}


func create_dm(_ message: String, to_pk: String, tags: [[String]], keypair: Keypair) -> NostrEvent?
{
    guard let privkey = keypair.privkey else {
        return nil
    }

    let iv = random_bytes(count: 16).bytes
    guard let shared_sec = get_shared_secret(privkey: privkey, pubkey: to_pk) else {
        return nil
    }
    let utf8_message = Data(message.utf8).bytes
    guard let enc_message = aes_encrypt(data: utf8_message, iv: iv, shared_sec: shared_sec) else {
        return nil
    }
    let enc_content = encode_dm_base64(content: enc_message.bytes, iv: iv)
    let ev = NostrEvent(content: enc_content, pubkey: keypair.pubkey, kind: 4, tags: tags)
    ev.calculate_id()
    ev.sign(privkey: privkey)
    return ev
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
