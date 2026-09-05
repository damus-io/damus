//
//  ReplyView.swift
//  damus
//
//  Created by William Casarin on 2022-04-17.
//

import SwiftUI

struct ReplyView: View {
    let replying_to: NostrEvent
    let damus: DamusState

    let original_pubkeys: [Pubkey]
    @Binding var filtered_pubkeys: Set<Pubkey>
    /// Whether the reply being composed is going out privately, gift wrapped to one person.
    ///
    /// This is `PostView.sending_privately` — the value the send path asks, not the lock's position —
    /// so the line here can never claim an audience the note is not actually going to.
    var sending_privately: Bool = false
    /// The single person a private reply is addressed to, when ``sending_privately``.
    var private_reply_recipient: Pubkey? = nil
    @State var participantsShown: Bool = false

    var references: [Pubkey] {
        original_pubkeys.filter { pk in
            !filtered_pubkeys.contains(pk)
        }
    }

    /// Who this reply is going to, said once and said truthfully.
    ///
    /// The public form lists the thread's `p` tags, which is also the set the user can edit by tapping
    /// through to ``ParticipantsView``. A private reply has neither property: its audience is exactly
    /// one key — the parent's author, not the thread — and the user cannot add to it or take from it.
    /// So the private form names that one person instead, wears the lock and the success tint the sent
    /// note will carry, and does not open the participants sheet, which would offer an edit that does
    /// nothing.
    ///
    /// This line is the composer's only statement of the audience; ``PostView/PrivacyButton`` is the
    /// control that sets it. Neither repeats the other.
    var ReplyingToSection: some View {
        HStack {
            Group {
                if sending_privately {
                    PrivatelyReplyingTo
                } else {
                    PubliclyReplyingTo
                }
            }
            .onTapGesture {
                participantsShown.toggle()
            }
            .allowsHitTesting(!sending_privately)
            .sheet(isPresented: $participantsShown) {
                if #available(iOS 16.0, *) {
                    ParticipantsView(damus_state: damus,
                                     original_pubkeys: self.original_pubkeys,
                                     filtered_pubkeys: $filtered_pubkeys)
                        .presentationDetents([.medium, .large])
                        .presentationDragIndicator(.visible)
                } else {
                    ParticipantsView(damus_state: damus,
                                     original_pubkeys: self.original_pubkeys,
                                     filtered_pubkeys: $filtered_pubkeys)
                }
            }
            .padding(.leading, 75)
            Spacer()
        }
    }

    @ViewBuilder
    var PubliclyReplyingTo: some View {
        let names = references
            .map { pubkey in
                let pk = pubkey
                let prof = try? damus.profiles.lookup(id: pk)
                return "@" + Profile.displayName(profile: prof, pubkey: pk).username.truncate(maxLength: 50)
            }
            .joined(separator: " ")
        if names.isEmpty {
            Text("Replying to \(Text("self", comment: "Part of a larger sentence 'Replying to self' in US English. 'self' indicates that the user is replying to themself and no one else.").foregroundColor(.accentColor).font(.footnote))", comment: "Indicating that the user is replying to the themself and no one else, where the parameter is 'self' in US English.")
                .foregroundColor(.gray)
                .font(.footnote)
        } else {
            Text("Replying to \(Text(verbatim: names).foregroundColor(.accentColor).font(.footnote))", comment: "Indicating that the user is replying to the following listed people.")
                .foregroundColor(.gray)
                .font(.footnote)
        }
    }

    @ViewBuilder
    var PrivatelyReplyingTo: some View {
        HStack(spacing: 5) {
            Image(systemName: "lock.fill")
            // A recipient we cannot name is not a case the composer can reach — the lock is only
            // offered when there is one — but naming nobody beats naming somebody wrong, so the
            // sentence still stands up without them.
            if let private_reply_recipient {
                let name = event_author_name(profiles: damus.profiles, pubkey: private_reply_recipient)
                Text("Replying privately to \(Text(verbatim: "@" + name))", comment: "Indicating that the user's reply will be encrypted and sent only to the named person, where the parameter is that person's username.")
            } else {
                Text("Replying privately", comment: "Indicating that the user's reply will be encrypted rather than posted publicly.")
            }
        }
        .font(.footnote)
        .foregroundColor(DamusColors.success)
        .accessibilityElement(children: .combine)
    }

    func line(height: CGFloat) -> some View {
        return Rectangle()
            .fill(Color.gray.opacity(0.25))
            .frame(width: 2, height: height)
            .offset(x: 25, y: 40)
            .padding(.leading)
    }

    var body: some View {
        VStack(alignment: .leading) {
            EventView(damus: damus, event: replying_to, options: [.no_action_bar])
                .padding()
                .background(GeometryReader { geometry in
                    let eventHeight = geometry.frame(in: .global).height
                    line(height: eventHeight)
                })
            
            ReplyingToSection
                .background(GeometryReader { geometry in
                    let replyingToHeight = geometry.frame(in: .global).height
                    line(height: replyingToHeight)
                })
        }
    }
}

struct ReplyView_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            ReplyView(replying_to: test_note,
                      damus: test_damus_state,
                      original_pubkeys: [],
                      filtered_pubkeys: .constant([]))
                .frame(height: 300)

            ReplyView(replying_to: test_longform_event.event,
                      damus: test_damus_state,
                      original_pubkeys: [],
                      filtered_pubkeys: .constant([]))
                .frame(height: 300)

            ReplyView(replying_to: test_note,
                      damus: test_damus_state,
                      original_pubkeys: [test_note.pubkey],
                      filtered_pubkeys: .constant([]),
                      sending_privately: true,
                      private_reply_recipient: test_note.pubkey)
                .frame(height: 300)
        }
    }
}
