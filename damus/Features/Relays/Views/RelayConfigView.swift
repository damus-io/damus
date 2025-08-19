//
//  RelayConfigView.swift
//  damus
//
//  Created by William Casarin on 2023-01-30.
//

import SwiftUI

enum RelayTab: Int, CaseIterable{
    case myRelays = 0
    case recommended
    
    var title: String{
        switch self {
        case .myRelays:
            return NSLocalizedString("My Relays", comment: "Title of the tab that shows the user's list of their own relays.")
        case .recommended:
            return NSLocalizedString("Recommended", comment: "Title of the tab that shows the list of relays recommended by Damus.")
        }
    }
}

struct RelayConfigView: View {
    let state: DamusState
    @State var relays: [RelayPool.RelayDescriptor]
    @State private var showActionButtons = false
    @State var show_add_relay: Bool = false
    @State var selectedTab = 0
    
    @Environment(\.dismiss) var dismiss
    
    init(state: DamusState) {
        self.state = state
        _relays = State(initialValue: state.nostrNetwork.ourRelayDescriptors)
        UITabBar.appearance().isHidden = true
    }
    
    var recommended: [RelayPool.RelayDescriptor] {
        let rs: [RelayPool.RelayDescriptor] = []
        let recommended_relay_addresses = get_default_bootstrap_relays()
        return recommended_relay_addresses.reduce(into: rs) { xs, x in
            xs.append(RelayPool.RelayDescriptor(url: x, info: .readWrite))
        }
    }

    var body: some View {
        NavigationView {
            ZStack(alignment: .bottom){
                TabView(selection: $selectedTab) {
                    RelayList(title: RelayTab.myRelays.title, relayList: relays, recommended: false)
                        .tag(0)

                    RelayList(title: RelayTab.recommended.title, relayList: recommended, recommended: true)
                        .tag(1)
                }
                ZStack{
                    HStack{
                        ForEach((RelayTab.allCases), id: \.self){ item in
                            Button{
                                selectedTab = item.rawValue
                            } label: {
                                CustomTabItem(title: item.title, isActive: (selectedTab == item.rawValue))
                            }
                        }
                    }
                }
                .frame(width: 235, height: 35)
                .background(.damusNeutral3)
                .cornerRadius(30)
                .padding(.horizontal, 26)
            }
        }
        .navigationTitle(NSLocalizedString("Relays", comment: "Title of relays view"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .navigationBarItems(leading: BackNav())
        .sheet(isPresented: $show_add_relay, onDismiss: { self.show_add_relay = false }) {
            AddRelayView(state: state)
                .presentationDetents([.height(300)])
                .presentationDragIndicator(.visible)
        }
        .toolbar {
            if state.keypair.privkey != nil && selectedTab == 0 {
                if showActionButtons {
                    Button(NSLocalizedString("Done", comment: "Button to leave edit mode for modifying the list of relays.")) {
                        withAnimation {
                            showActionButtons.toggle()
                        }
                    }
                } else {
                    Button(NSLocalizedString("Edit", comment: "Button to enter edit mode for modifying the list of relays.")) {
                        withAnimation {
                            showActionButtons.toggle()
                        }
                    }
                }
            }
        }
        .onReceive(handle_notify(.relays_changed)) { _ in
            self.relays = state.nostrNetwork.ourRelayDescriptors
        }
        .onAppear {
            notify(.display_tabbar(false))
        }
        .onDisappear {
            notify(.display_tabbar(true))
        }
        .ignoresSafeArea(.all)
    }
    
    func RelayList(title: String, relayList: [RelayPool.RelayDescriptor], recommended: Bool) -> some View {
        ScrollView(showsIndicators: false) {
            HStack {
                Text(title)
                    .font(.system(size: 32, weight: .bold))
                
                
                Spacer()
                
                if state.keypair.privkey != nil {
                    Button(action: {
                        show_add_relay.toggle()
                    }) {
                        HStack {
                            Text("Add relay", comment: "Button text to add a relay")
                                .padding(10)
                        }
                    }
                    .buttonStyle(NeutralButtonStyle())
                }
            }
            .padding(.top, 5)

            ForEach(relayList, id: \.url) { relay in
                Group {
                    RelayView(state: state, relay: relay.url, showActionButtons: $showActionButtons, recommended: recommended)
                    Divider()
                }
            }
            
            Spacer()
                .padding(25)
        }
        .padding(.horizontal)
    }
}

extension RelayConfigView{
    func CustomTabItem(title: String, isActive: Bool) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 12, weight: isActive ? .bold : .regular))
                .foregroundColor(isActive ? .damusAdaptableBlack : .damusAdaptableBlack.opacity(0.7))
        }
        .frame(width: 110, height: 30)
        .background(isActive ? .damusAdaptableWhite.opacity(0.9) : .clear)
        .cornerRadius(30)
    }
}

struct RelayConfigView_Previews: PreviewProvider {
    static var previews: some View {
        RelayConfigView(state: test_damus_state)
    }
}
