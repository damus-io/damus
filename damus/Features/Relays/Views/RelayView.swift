//
//  RelayView.swift
//  damus
//
//  Created by William Casarin on 2022-10-16.
//

import SwiftUI

struct RelayView: View {
    let state: DamusState
    let relay: RelayURL
    let recommended: Bool
    /// Disables navigation link
    let disableNavLink: Bool
    /// Optional descriptor for recommended relays (not yet connected)
    let descriptor: RelayPool.RelayDescriptor?
    @ObservedObject private var model_cache: RelayModelCache

    @State var relay_state: Bool
    @Binding var showActionButtons: Bool

    init(state: DamusState, relay: RelayURL, showActionButtons: Binding<Bool>, recommended: Bool, disableNavLink: Bool = false, descriptor: RelayPool.RelayDescriptor? = nil) {
        self.state = state
        self.relay = relay
        self.recommended = recommended
        self.model_cache = state.relay_model_cache
        _showActionButtons = showActionButtons
        self._relay_state = State(initialValue: state.nostrNetwork.getRelay(relay) == nil)
        self.disableNavLink = disableNavLink
        self.descriptor = descriptor
    }

    /// Check if relay URL is purplepag.es (for showing Profile badge)
    static func isPurplePagesRelay(_ relay: RelayURL) -> Bool {
        relay.absoluteString.contains("purplepag.es")
    }

    /// Whether this relay is profile-only (for showing Profile badge)
    var isProfileOnly: Bool {
        if Self.isPurplePagesRelay(relay) {
            return true
        }
        return state.nostrNetwork.getRelay(relay)?.descriptor.isProfilesOnly ?? descriptor?.isProfilesOnly ?? false
    }

    /// Whether relay needs to be added (true = show Add button, false = show Added button)
    var needsToBeAdded: Bool {
        return relay_state
    }

    var body: some View {
        Group {
            HStack {
                if let privkey = state.keypair.privkey {
                    if showActionButtons && !recommended {
                        RemoveButton(privkey: privkey, showText: false)
                    }
                }

                let meta = model_cache.model(with_relay_id: relay)?.metadata
            
                RelayPicView(relay: relay, icon: meta?.icon, size: 55, highlight: .none, disable_animation: false)

                VStack(alignment: .leading) {
                    HStack {
                        Text(meta?.name ?? relay.url.host() ?? relay.url.absoluteString)
                            .font(.headline)
                            .padding(.bottom, 2)
                            .lineLimit(1)
                        RelayType(
                            is_paid: state.relay_model_cache.model(with_relay_id: relay)?.metadata.is_paid ?? false,
                            is_profile_only: isProfileOnly
                        )

                        if relay.absoluteString.hasSuffix(".onion") {
                            Image("tor")
                                .resizable()
                                .interpolation(.none)
                                .frame(width: 20, height: 20)
                        }
                    }
                    Text(relay.absoluteString)
                        .font(.subheadline)
                        .foregroundColor(.gray)
                        .lineLimit(1)
                        .contextMenu {
                            CopyAction(relay: relay.absoluteString)

                            if let privkey = state.keypair.privkey {
                                RemoveButton(privkey: privkey, showText: true)
                            }
                        }
                }
                    
                Spacer()
                
                if recommended {
                    if let keypair = state.keypair.to_full() {
                        VStack(alignment: .center) {
                            if needsToBeAdded {
                                AddButton(keypair: keypair)
                            } else {
                                Button(action: {
                                    Task { await remove_action(privkey: keypair.privkey) }
                                }) {
                                    Text("Added", comment: "Button to show relay server is already added to list.")
                                        .font(.caption)
                                }
                                .buttonStyle(NeutralButtonShape.capsule.style)
                                .opacity(0.5)
                            }
                        }
                        .padding(.horizontal, 5)
                    }
                } else {
                    if let relay_connection {
                        RelayStatusView(connection: relay_connection)
                    }
                    
                    if !disableNavLink {
                        Image("chevron-large-right")
                            .resizable()
                            .frame(width: 15, height: 15)
                            .foregroundColor(.gray)
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .onReceive(handle_notify(.relays_changed)) { _ in
            self.relay_state = state.nostrNetwork.getRelay(relay) == nil
        }
        .onTapGesture {
            if !disableNavLink {
                state.nav.push(route: Route.RelayDetail(relay: relay, metadata: model_cache.model(with_relay_id: relay)?.metadata))
            }
        }
    }
    
    private var relay_connection: RelayConnection? {
        state.nostrNetwork.getRelay(relay)?.connection
    }
    
    func add_action(keypair: FullKeypair) async {
        do {
            try await state.nostrNetwork.userRelayList.insert(relay: NIP65.RelayList.RelayItem(url: relay, rwConfiguration: .readWrite))
        }
        catch {
            present_sheet(.error(error.humanReadableError))
        }
    }

    func remove_action(privkey: Privkey) async {
        do {
            try await state.nostrNetwork.userRelayList.remove(relayURL: relay)
        }
        catch {
            present_sheet(.error(error.humanReadableError))
        }
    }
    
    func AddButton(keypair: FullKeypair) -> some View {
        Button(action: {
            Task { await add_action(keypair: keypair) }
        }) {
            Text("Add", comment: "Button to add relay server to list.")
                .font(.caption)
        }
        .buttonStyle(NeutralButtonShape.capsule.style)
    }
    
    func CopyAction(relay: String) -> some View {
        Button {
            UIPasteboard.general.setValue(relay, forPasteboardType: "public.plain-text")
        } label: {
            Label(NSLocalizedString("Copy", comment: "Button to copy a relay server address."), image: "copy2")
        }
    }
        
    func RemoveButton(privkey: Privkey, showText: Bool) -> some View {
        Button(action: {
            Task { await remove_action(privkey: privkey) }
        }) {
            if showText {
                Text("Disconnect", comment: "Button to disconnect from a relay server.")
            }
            
            Image("minus-circle")
                .resizable()
                .frame(width: 20, height: 20)
                .foregroundColor(.red)
                .padding(.leading, 5)
        }
    }
}

struct RelayView_Previews: PreviewProvider {
    static var previews: some View {
        RelayView(state: test_damus_state, relay: RelayURL("wss://relay.damus.io")!, showActionButtons: .constant(false), recommended: false)
    }
}
