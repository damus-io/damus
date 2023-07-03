//
//  RelayDetailView.swift
//  damus
//
//  Created by Joel Klabo on 2/1/23.
//

import SwiftUI

struct RelayDetailView: View {
    let state: DamusState
    let relay: String
    let nip11: RelayMetadata
    
    @Environment(\.dismiss) var dismiss
    
    func check_connection() -> Bool {
        for relay in state.pool.relays {
            if relay.id == self.relay {
                return true
            }
        }
        return false
    }
    
    func FieldText(_ str: String?) -> some View {
        if let s = str {
            return Text(verbatim: s)
        } else {
            return Text("No data available", comment: "Text indicating that there is no data available to show for specific metadata about a relay server.")
        }
    }
    
    var body: some View {
        Group {
            Form {
                
                if let privkey = state.keypair.privkey {
                    if check_connection() {
                        Button(action: {
                            guard let ev = state.contacts.event else {
                                return
                            }

                            let descriptors = state.pool.our_descriptors
                            guard let new_ev = remove_relay( ev: ev, current_relays: descriptors, privkey: privkey, relay: relay) else {
                                return
                            }

                            process_contact_event(state: state, ev: new_ev)
                            state.postbox.send(new_ev)
                            dismiss()
                        }) {
                            Text("Disconnect From Relay", comment: "Button to disconnect from the relay.")
                        }
                    } else {
                        Button(action: {
                            guard let ev_before_add = state.contacts.event else {
                                return
                            }
                            guard let ev_after_add = add_relay(ev: ev_before_add, privkey: privkey, current_relays: state.pool.our_descriptors, relay: relay, info: .rw) else {
                                return
                            }
                            process_contact_event(state: state, ev: ev_after_add)
                            state.postbox.send(ev_after_add)
                            dismiss()
                        }) {
                            Text("Connect To Relay", comment: "Button to connect to the relay.")
                        }
                    }
                }
                
                if let pubkey = nip11.pubkey {
                    Section(NSLocalizedString("Admin", comment: "Label to display relay contact user.")) {
                        UserViewRow(damus_state: state, pubkey: pubkey)
                            .onTapGesture {
                                state.nav.push(route: Route.ProfileByKey(pubkey: pubkey))
                            }
                    }
                }
                if let relay_connection {
                    Section(NSLocalizedString("Relay", comment: "Label to display relay address.")) {
                        HStack {
                            Text(relay)
                            Spacer()
                            RelayStatusView(connection: relay_connection)
                        }
                    }
                }
                if nip11.is_paid {
                    Section(content: {
                        RelayPaidDetail(payments_url: nip11.payments_url)
                    }, header: {
                        Text("Paid Relay", comment: "Section header that indicates the relay server requires payment.")
                    }, footer: {
                        Text("This is a paid relay, you must pay for notes to be accepted.", comment: "Footer description that explains that the relay server requires payment to post.")
                    })
                }
                
                Section(NSLocalizedString("Description", comment: "Label to display relay description.")) {
                    FieldText(nip11.description)
                }
                Section(NSLocalizedString("Contact", comment: "Label to display relay contact information.")) {
                    FieldText(nip11.contact)
                }
                Section(NSLocalizedString("Software", comment: "Label to display relay software.")) {
                    FieldText(nip11.software)
                }
                Section(NSLocalizedString("Version", comment: "Label to display relay software version.")) {
                    FieldText(nip11.version)
                }
                if let nips = nip11.supported_nips, nips.count > 0 {
                    Section(NSLocalizedString("Supported NIPs", comment: "Label to display relay's supported NIPs.")) {
                        Text(nipsList(nips: nips))
                    }
                }
            }
        }
        .onReceive(handle_notify(.switched_timeline)) { notif in
            dismiss()
        }
        .navigationTitle(nip11.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private func nipsList(nips: [Int]) -> AttributedString {
        var attrString = AttributedString()
        let lastNipIndex = nips.count - 1
        for (index, nip) in nips.enumerated() {
            if let link = NIPURLBuilder.url(forNIP: nip) {
                let nipString = NIPURLBuilder.formatNipNumber(nip: nip)
                var nipAttrString = AttributedString(stringLiteral: nipString)
                nipAttrString.link = link
                attrString = attrString + nipAttrString
                if index < lastNipIndex {
                    attrString = attrString + AttributedString(stringLiteral: ", ")
                }
            }
        }
        return attrString
    }
    
    private var relay_connection: RelayConnection? {
        state.pool.get_relay(relay)?.connection
    }
}

struct RelayDetailView_Previews: PreviewProvider {
    static var previews: some View {
        let metadata = RelayMetadata(name: "name", description: "desc", pubkey: "pubkey", contact: "contact", supported_nips: [1,2,3], software: "software", version: "version", limitation: Limitations.empty, payments_url: "https://jb55.com")
        RelayDetailView(state: test_damus_state(), relay: "relay", nip11: metadata)
    }
}
