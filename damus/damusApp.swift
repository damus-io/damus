//
//  damusApp.swift
//  damus
//
//  Created by William Casarin on 2022-04-01.
//

import SwiftUI
import SDWebImage
import SDWebImageSVGCoder

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
    
    var body: some View {
        Group {
            if let kp = keypair, !needs_setup {
                ContentView(keypair: kp)
            } else {
                SetupView()
                    .onReceive(handle_notify(.login)) { notif in
                        needs_setup = false
                        keypair = get_saved_keypair()
                    }
            }
        }
        .dynamicTypeSize(.xSmall ... .xxxLarge)
        .onReceive(handle_notify(.logout)) { _ in
            try? clear_keypair()
            keypair = nil
        }
        .onAppear {
            keypair = get_saved_keypair()
            
            let responseModifier = SDWebImageDownloaderResponseModifier { (response) -> URLResponse? in
                let contentLength = response.expectedContentLength

                // Content-Length header is optional (-1 when missing)
                if (contentLength != -1 && contentLength > 20_971_520) {
                    return nil
                }

                return response
            }

            SDWebImageDownloader.shared.responseModifier = responseModifier

            SDImageCoderHelper.defaultScaleDownLimitBytes = 5_242_880
            SDImageCodersManager.shared.addCoder(SDImageAWebPCoder.shared)
            SDImageCodersManager.shared.addCoder(SDImageSVGCoder.shared)
        }
    }
}

func needs_setup() -> Keypair? {
    return get_saved_keypair()
}
    
