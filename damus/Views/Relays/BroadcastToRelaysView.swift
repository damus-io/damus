//
//  BroadcastToRelaysView.swift
//  damus
//
//  Created by devandsev on 2/4/23.
//

import SwiftUI

extension BroadcastToRelaysView {
    
    class ViewState: ObservableObject {
        let damusState: DamusState
        @Published var relayRows: [RowState] = []
        
        var hasExcludedRelays: Bool { relayRows.contains { !$0.isSelected } }
        var selectedRelays: [RelayDescriptor] { relayRows.filter { $0.isSelected }.map { $0.relay } }
        var limitingRelayIds: [String]? {
            guard hasExcludedRelays else {
                return nil
            }
            return selectedRelays.map { get_relay_id($0.url) }
        }
        
        init(state: DamusState) {
            damusState = state
            relayRows = state.pool.descriptors.map { RowState(relay: $0, isSelected: true) }
        }
    }
    
    struct RowState: Equatable {
        let relay: RelayDescriptor
        var isSelected: Bool
    }
}

/// A list of relays you can select to send your event to
///
/// Can be presented in 2 modes:
/// - If `broadCastEvent` is nil, user selects relays, goes to the previous screen and the post/reply will be sent to selected relays only. Presented in this mode from `PostView` and `ReplyView` by tapping relays button.
/// - If `broadCastEvent` is not nil, there will be a "Broadcast" button in the navBar to broadcast this event to selected relays. Presented in this mode by long-pressing a post and choosing "Broadcast".
struct BroadcastToRelaysView: View {
    @ObservedObject var state: ViewState
   
    let broadCastEvent: NostrEvent? 
    
    @Environment(\.presentationMode) var presentationMode
    
    func selectAll() {
        $state.relayRows.forEach { $0.wrappedValue.isSelected = true }
    }
    
    func selectOne() {
        guard let firstSelectedRow = $state.relayRows.first(where: { $0.wrappedValue.isSelected }) else {
            $state.relayRows.forEach { $0.wrappedValue.isSelected = false }
            $state.relayRows.first?.wrappedValue.isSelected = true
            return
        }
        
        $state.relayRows.forEach { $0.wrappedValue.isSelected = false }
        firstSelectedRow.wrappedValue.isSelected = true
    }
    
    func dismiss() {
        self.presentationMode.wrappedValue.dismiss()
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section {
                    List(Array($state.relayRows), id: \.wrappedValue.relay.url) { $relayRow in
                        SelectableRowView(isSelected: $relayRow.isSelected,
                                          shouldChangeSelection: {
                            return !relayRow.isSelected || $state.relayRows.filter { $0.wrappedValue.isSelected }.count > 1
                            
                        } ) {
                            RelayView(state: state.damusState, relay: relayRow.relay.url.absoluteString)
                        }
                    }
                }
                header: {
                    HStack {
                        Text("Relays to send to", comment: "Section header text for relay server list. On this screen user can select to which specific relays the post should be sent.")
                        Spacer()
                        Button(NSLocalizedString("All", comment: "Button to select all relays in the list to which the post will be sent")) {
                            self.selectAll()
                        }
                        .disabled(!state.hasExcludedRelays)
                        Button(NSLocalizedString("One", comment: "Button to select only one relay from the list to which the post will be sent")) {
                            self.selectOne()
                        }
                        .disabled(state.selectedRelays.count == 1)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if broadCastEvent != nil {
                        Button(action: {
                            dismiss()
                        }) {
                            Text("Cancel", comment: "Navigation bar button to cancel broadcasting the user's note to all of the user's connected relay servers.")
                        }.foregroundColor(.primary)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if broadCastEvent != nil {
                        Button(action: {
                            if let broadCastEvent = broadCastEvent {
                                state.damusState.pool.send(.event(broadCastEvent), to: state.limitingRelayIds)
                                dismiss()
                            }
                        }) {
                            Text("Broadcast", comment: "Navigation bar button to confirm broadcasting the user's note to all of the user's connected relay servers.")
                        }
                    }
                }
            }
        }
    }
}
