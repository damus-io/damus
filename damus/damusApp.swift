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
    @State var needs_setup = true;
    
    var body: some View {
        if needs_setup {
            SetupView()
                .onReceive(handle_notify(.login)) { notif in
                    needs_setup = false
                }
        } else {
            ContentView()
        }
    }
}

func needs_setup() -> Bool {
    let _ = get_saved_privkey()
    return true
}
    
