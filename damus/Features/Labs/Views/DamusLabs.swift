//
//  DamusLabs.swift
//  damus
//
//  Created by eric on 10/17/25.
//

import SwiftUI
import StoreKit

struct DamusLabsView: View {
    let damus_state: DamusState
    @State var purple_account: DamusPurple.Account?

    @State var show_intro_sheet: Bool = true
    @State private var shouldDismissView = false
    
    @Environment(\.dismiss) var dismiss
    
    init(damus_state: DamusState) {
        self.damus_state = damus_state
        self.purple_account = nil
    }

    var body: some View {
        NavigationView {
            PurpleBackdrop {
                VStack {
                    MainContent
                }
            }
            .navigationBarHidden(true)
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .navigationBarItems(leading: BackNav())
        }
        .onReceive(handle_notify(.switched_timeline)) { _ in
            dismiss()
        }
        .onAppear {
            notify(.display_tabbar(false))
        }
        .task {
            if damus_state.purple.enable_purple {
                self.purple_account = try? await damus_state.purple.get_maybe_cached_account(pubkey: damus_state.pubkey)
            }
        }
        .ignoresSafeArea(.all)
    }
    
    var MainContent: some View {
        VStack {
            if let purple_account, purple_account.active == true {
                DamusLabsExperiments(damus_state: damus_state, settings: damus_state.settings)
            } else {
                LabsLogoView()
                    .padding(.top, 125)
                LabsIntroductionView(damus_state: damus_state)
            }
        }
    }
}

struct DamusLabsView_Previews: PreviewProvider {
    static var previews: some View {
        DamusLabsView(damus_state: test_damus_state)
    }
}
