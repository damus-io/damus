//
//  DeeplinkManager.swift
//  damus
//
//  Created by Ben Weeks on 1/5/23.
//  Ref: https://www.createwithswift.com/creating-a-custom-app-launch-experience-in-swiftui-with-deep-linking/

import Foundation

class DeeplinkManager {
    
    // Possible destinations
    enum DeeplinkTarget: Equatable {
        case home
        case profile(pubkey: String)
    }
    
    class DeepLinkConstants {
        static let scheme = "nostr"
        static let host = "io.damus.nostr"
        static let path = "/profile"
        static let query = "pubkey"
        
        // Some example deep links could be:
        // nostr://npub1jutptdc2m8kgjmudtws095qk2tcale0eemvp4j2xnjnl4nh6669slrf04x
        // nostr://io.damus.nostr/npub1jutptdc2m8kgjmudtws095qk2tcale0eemvp4j2xnjnl4nh6669slrf04x
        // nostr://io.damus.nostr/profile/pubkey=npub1jutptdc2m8kgjmudtws095qk2tcale0eemvp4j2xnjnl4nh6669slrf04x
    }
    
    // Function to handle the management of the Urls (and validate)
    func manage(url: URL) -> DeeplinkTarget {
        /*
        guard url.scheme == DeepLinkConstants.scheme,
              url.host == DeepLinkConstants.host,
              url.path == DeepLinkConstants.path
        else {
            print("Missing Url properties")
            return.home
        }
        */
        
        if (url.scheme != "nostr") { return .home }
        //guard let pubkey = url.path else { return .home }
        var pubkey = url.path.replacingOccurrences(of: "/", with: "")
        //guard let pubkey = url.path else { return .home }
        if !pubkey.lowercased().starts(with: "npub") { return .home }
        return .profile(pubkey: pubkey)
    }
}
