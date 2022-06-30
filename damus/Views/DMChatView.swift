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
    @Binding var events: [NostrEvent]
    @State var message: String = ""

    var Messages: some View {
        ScrollViewReader { scroller in
            ScrollView {
                VStack(alignment: .leading) {
                    ForEach(Array(zip(events, events.indices)), id: \.0.id) { (ev, ind) in
                        DMView(event: events[ind], damus_state: damus_state)
                            .event_context_menu(ev)
                    }
                    Color.white.opacity(0)
                        .id("endblock")
                        .frame(height: 80)
                }
            }
            .onAppear {
                scroller.scrollTo("endblock")
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
                ProfilePicView(pubkey: pubkey, size: 24, highlight: .none, image_cache: damus_state.image_cache, profiles: damus_state.profiles)

                ProfileName(pubkey: pubkey, profile: profile)
            }
        }
        .buttonStyle(PlainButtonStyle())
    }

    var InputField: some View {
        TextField("New Message", text: $message)
            .padding([.leading], 12)
            .padding([.top, .bottom], 8)
            .background {
                InputBackground()
            }
            .foregroundColor(Color.primary)
            .cornerRadius(20)
            .padding([.leading, .top, .bottom], 8)
    }

    @Environment(\.colorScheme) var colorScheme

    func InputBackground() -> some View {
        if colorScheme == .dark {
            return Color.black.brightness(0.1)
        } else {
            return Color.gray.brightness(0.35)
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

            HStack {
                InputField

                Button(role: .none, action: send_message) {
                    Label("", systemImage: "arrow.right.circle")
                        .font(.title)
                }
            }
        }
        .frame(height: 70)
    }

    func send_message() {
        guard let dm = create_dm(message, to_pk: pubkey, keypair: damus_state.keypair) else {
            print("error creating dm")
            return
        }

        message = ""

        damus_state.pool.send(.event(dm))
    }

    var body: some View {
        ZStack {
            Messages
                .padding([.top, .leading, .trailing], 10)
                .dismissKeyboardOnTap()

            VStack {
                Spacer()

                Footer
            }
        }
        .toolbar { Header }
    }
}

struct DMChatView_Previews: PreviewProvider {
    static var previews: some View {
        let ev = NostrEvent(content: "hi", pubkey: "pubkey", kind: 1, tags: [])
        let evs = Binding<[NostrEvent]>.init(
            get: { [ev] },
            set: { _ in })

        DMChatView(damus_state: test_damus_state(), pubkey: "pubkey", events: evs)
    }
}


func create_dm(_ message: String, to_pk: String, keypair: Keypair) -> NostrEvent?
{
    guard let privkey = keypair.privkey else {
        return nil
    }

    let tags = [["p", to_pk]]
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
