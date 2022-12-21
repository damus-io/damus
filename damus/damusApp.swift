//
//  damusApp.swift
//  damus
//
//  Created by William Casarin on 2022-04-01.
//

import SwiftUI

@main
struct damusApp: App {
    var body: some Scene {
        WindowGroup {
            MainView()
        }
        
    }
    

}

struct MainView: View {
    @State var needs_setup = false;
    @State var keypair: Keypair? = nil;
    
    @ObservedObject var viewModel: DamusViewModel = DamusViewModel()
    
    var body: some View {
        Group {
            if let kp = keypair, !needs_setup {
                ContentView(keypair: kp)
                    .environmentObject(viewModel)
            } else {
                SetupView()
                    .onReceive(handle_notify(.login)) { notif in
                        needs_setup = false
                        keypair = get_saved_keypair()
                    }
            }
        }
        .onReceive(handle_notify(.logout)) { _ in
            clear_keypair()
            keypair = nil
        }
        .onAppear {
            keypair = get_saved_keypair()
        }
    }
}

func needs_setup() -> Keypair? {
    return get_saved_keypair()
}
    
