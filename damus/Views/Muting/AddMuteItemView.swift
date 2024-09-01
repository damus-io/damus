//
//  AddMuteItemView.swift
//  damus
//
//  Created by Charlie Fish on 1/10/24.
//
import SwiftUI

struct AddMuteItemView: View {
    let state: DamusState
    @State var new_text: String = ""
    @State var expiration: DamusDuration = .indefinite

    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack {
            Text("Add mute item", comment: "Title text to indicate user to an add an item to their mutelist.")
                .font(.system(size: 20, weight: .bold))
                .padding(.vertical)

            Divider()
                .padding(.bottom)

            Picker(selection: $expiration) {
                ForEach(DamusDuration.allCases, id: \.self) { duration in
                    Text(duration.title).tag(duration)
                }
            } label: {
                Text("Duration", comment: "The duration in which to mute the given item.")
            }


            HStack {
                Label("", image: "copy2")
                    .onTapGesture {
                    if let pasted_text = UIPasteboard.general.string {
                        self.new_text = pasted_text
                    }
                }
                TextField(NSLocalizedString("npub, #hashtag, phrase", comment: "Placeholder example for relay server address."), text: $new_text)
                    .autocorrectionDisabled(true)
                    .textInputAutocapitalization(.never)

                Label("", image: "close-circle")
                    .foregroundColor(.accentColor)
                    .opacity((new_text == "") ? 0.0 : 1.0)
                    .onTapGesture {
                        self.new_text = ""
                    }
            }
            .padding(10)
            .background(.secondary.opacity(0.2))
            .cornerRadius(10)

            Button(action: {
                let expiration_date: Date? = self.expiration.date_from_now
                let mute_item: MuteItem? = {
                    if new_text.starts(with: "npub") {
                        if let pubkey: Pubkey = bech32_pubkey_decode(new_text) {
                            return .user(pubkey, expiration_date)
                        } else {
                            return nil
                        }
                    } else if new_text.starts(with: "#") {
                        // Remove the starting `#` character
                        return .hashtag(Hashtag(hashtag: String("\(new_text)".dropFirst())), expiration_date)
                    } else {
                        return .word(new_text, expiration_date)
                    }
                }()

                // Actually update & relay the new mute list
                if let mute_item {
                    let existing_mutelist = state.mutelist_manager.event

                    guard
                        let full_keypair = state.keypair.to_full(),
                        let mutelist = create_or_update_mutelist(keypair: full_keypair, mprev: existing_mutelist, to_add: mute_item)
                    else {
                        return
                    }

                    state.mutelist_manager.set_mutelist(mutelist)
                    state.postbox.send(mutelist)
                }

                new_text = ""

                this_app.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)

                dismiss()
            }) {
                HStack {
                    Text(verbatim: "Add mute item")
                        .bold()
                }
                .frame(minWidth: 300, maxWidth: .infinity, alignment: .center)
            }
            .buttonStyle(GradientButtonStyle(padding: 10))
            .padding(.vertical)

            Spacer()
        }
        .padding()
    }
}

struct AddMuteItemView_Previews: PreviewProvider {
    static var previews: some View {
        AddMuteItemView(state: test_damus_state)
    }
}
