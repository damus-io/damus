//
//  damusApp.swift
//  damus
//
//  Created by William Casarin on 2022-04-01.
//

import SwiftUI

@main
struct damusApp: App {
    @State var needs_setup = false;
    @State var keypair: Keypair? = nil;
    @State var deeplinkTarget: DeeplinkManager.DeeplinkTarget?
    @State var damus_state: DamusState? = nil
    
    var body: some Scene {
        WindowGroup {
            Group {
                if let kp = keypair, !needs_setup {
                    switch self.deeplinkTarget {
                        case .home:
                            // HomeView(withDeepLink: true)
                            ContentView(keypair: kp)
                        case .profile(let pubkey):
                            //print(queryInfo)
                            //ContentView(keypair: kp)
                            if let damus = self.damus_state {
                                let prof_model = ProfileModel(pubkey: pubkey, damus: damus)
                                let followers = FollowersModel(damus_state: damus, target: pubkey)
                                ProfileView(damus_state: damus, profile: prof_model, followers: followers)
                            }
                        case .none:
                            // HomeView(withDeepLink: false)
                            //print("aaa")
                            ContentView(keypair: kp)
                        default:
                            ContentView(keypair: kp)
                    }
                } else {
                    SetupView()
                        .onReceive(handle_notify(.login)) { notif in
                            needs_setup = false
                            keypair = get_saved_keypair()
                        }
                }
            }
            .onOpenURL { url in
                print(url)
                // Ref: https://www.createwithswift.com/creating-a-custom-app-launch-experience-in-swiftui-with-deep-linking/
                let deeplinkManager = DeeplinkManager()
                let deeplink = deeplinkManager.manage(url: url)
                self.deeplinkTarget = deeplink
            }
            .onReceive(handle_notify(.logout)) { _ in
                try? clear_keypair()
                keypair = nil
            }
            .onAppear {
                keypair = get_saved_keypair()
            }
        }
    }
}

func needs_setup() -> Keypair? {
    return get_saved_keypair()
}
    
