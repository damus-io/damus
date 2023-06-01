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
    @State private var textHeight: CGFloat = 0
    
    var pubkey: Pubkey {
        dms.pubkey
    }

    // Group events by date and then by pubkey and sort them by creation time
    func groupEventsByDateAndPubkey(events: [NostrEvent]) -> [Date: [String: [NostrEvent]]] {
        let groups = Dictionary(grouping: events) { event in
            Calendar.current.startOfDay(for: Date(timeIntervalSince1970: TimeInterval(event.created_at)))
        }.mapValues { events in
            var lastEventDate: Date?
            var groupCounter = 0

            var eventGroups = [String: [NostrEvent]]()

            for event in events {
                let currentEventDate = Date(timeIntervalSince1970: TimeInterval(event.created_at))
                defer { lastEventDate = currentEventDate }

                let pubkey = event.pubkey
                if let lastDate = lastEventDate,
                   currentEventDate.timeIntervalSince(lastDate) <= 120,
                   let lastEvent = eventGroups["\(groupCounter)-\(pubkey)"]?.last,
                   lastEvent.pubkey == pubkey {
                    eventGroups["\(groupCounter)-\(pubkey)"]?.append(event)
                } else {
                    groupCounter += 1
                    eventGroups["\(groupCounter)-\(pubkey)"] = [event]
                }
            }

            return eventGroups.mapValues { $0.sorted(by: { $0.created_at < $1.created_at }) }
        } as [Date: [String: [NostrEvent]]]

        return groups
    }

    var Messages: some View {
        ScrollViewReader { scroller in
            ScrollView {
                LazyVStack(alignment: .leading) {
                    ForEach(Array(zip(dms.events, dms.events.indices)), id: \.0.id) { (ev, ind) in
                        DMView(event: dms.events[ind], damus_state: damus_state)
                            .contextMenu{MenuItems(event: ev, keypair: damus_state.keypair, target_pubkey: ev.pubkey, bookmarks: damus_state.bookmarks, muted_threads: damus_state.muted_threads, settings: damus_state.settings)}
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
        return NavigationLink(value: Route.ProfileByKey(pubkey: pubkey)) {
            HStack {
                ProfilePicView(pubkey: pubkey, size: 24, highlight: .none, profiles: damus_state.profiles, disable_animation: damus_state.settings.disable_animation)

                ProfileName(pubkey: pubkey, profile: profile, damus: damus_state)
            }
        }
        .buttonStyle(PlainButtonStyle())
    }

    var InputField: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(alignment: .leading) {
                ZStack(alignment: .topLeading) {
                    HStack {
                         TextEditor(text: $dms.draft)
                             .font(.body)
                             .frame(minHeight: 15, maxHeight: 150)
                             .foregroundColor(Color.primary)
                             .padding(.horizontal, 10)
                             .fixedSize(horizontal: false, vertical: true)
                             .focused($focusedField, equals: .message)
                             .overlay(
                                 GeometryReader { geo in
                                     Color.clear
                                         .preference(key: ViewHeightKey.self, value: geo.size.height)
                                 }
                             )
                             .onPreferenceChange(ViewHeightKey.self) {
                                 textHeight = $0
                             }
                             .onChange(of: dms.draft) { _ in
                                 DispatchQueue.main.async {
                                     textHeight = getTextHeight()
                                 }
                             }
                         
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
                                     .foregroundStyle(LINEAR_GRADIENT)
                             }
                         }
                     }
                    
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(style: .init(lineWidth: 0.75))
                        .foregroundColor(.secondary.opacity(0.35))
                    
                    Text(dms.draft == "" ? placeholder : "")
                        .font(.body)
                        .padding(.leading, 15)
                        .foregroundColor(.gray)
                        .opacity(dms.draft == "" ? 0.35 : 0)
                        .frame(minHeight: 15, maxHeight: 150, alignment: .center)
                        .onTapGesture(perform: {
                            focusedField = .message
                        })
                }
            }
        }
        .frame(height: textHeight)
    }

    private func getTextHeight() -> CGFloat {
        let textHeight = dms.draft.isEmpty ? 15 : dms.draft.getHeight(width: UIScreen.main.bounds.width - 32, font: .systemFont(ofSize: 16))
        let height = textHeight < 150 ? textHeight : 150
        return height + 16
    }

    var Footer: some View {
      VStack {
          Divider()
          InputField
              .padding(10)
              .padding(.top, -5)
      }
    }

    func send_message() {
        let tags = [["p", pubkey.hex()]]
        let post_blocks = parse_post_blocks(content: dms.draft)
        let content = render_blocks(blocks: post_blocks)

        guard let dm = create_dm(content, to_pk: pubkey, tags: tags, keypair: damus_state.keypair) else {
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
        let ev = NostrEvent(content: "hi", keypair: test_keypair, kind: 1, tags: [])!

        let model = DirectMessageModel(events: [ev], our_pubkey: test_pubkey, pubkey: test_pubkey)

        DMChatView(damus_state: test_damus_state(), dms: model)
    }
}

enum EncEncoding {
    case base64
    case bech32
}

func encrypt_message(message: String, privkey: Privkey, to_pk: Pubkey, encoding: EncEncoding = .base64) -> String? {
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

func create_encrypted_event(_ message: String, to_pk: Pubkey, tags: [[String]], keypair: FullKeypair, created_at: UInt32, kind: UInt32) -> NostrEvent? {
    let privkey = keypair.privkey
    
    guard let enc_content = encrypt_message(message: message, privkey: privkey, to_pk: to_pk) else {
        return nil
    }
    
    return NostrEvent(content: enc_content, keypair: keypair.to_keypair(), kind: kind, tags: tags, createdAt: created_at)
}

func create_dm(_ message: String, to_pk: Pubkey, tags: [[String]], keypair: Keypair, created_at: UInt32? = nil) -> NostrEvent?
{
    let created = created_at ?? UInt32(Date().timeIntervalSince1970)

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

