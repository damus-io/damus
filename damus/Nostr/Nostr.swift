//
//  Nostr.swift
//  damus
//
//  Created by William Casarin on 2022-04-07.
//

import Foundation

struct Profile: Codable {
    var value: [String: String]
    
    init (name: String?, display_name: String?, about: String?, picture: String?, website: String?, lud06: String?, lud16: String?, nip05: String?) {
        self.value = [:]
        self.name = name
        self.display_name = display_name
        self.about = about
        self.picture = picture
        self.website = website
        self.lud06 = lud06
        self.lud16 = lud16
        self.nip05 = nip05
    }
    
    var display_name: String? {
        get { return value["display_name"]; }
        set(s) { value["display_name"] = s }
    }
    
    var name: String? {
        get { return value["name"]; }
        set(s) { value["name"] = s }
    }
    
    var about: String? {
        get { return value["about"]; }
        set(s) { value["about"] = s }
    }
    
    var picture: String? {
        get { return value["picture"]; }
        set(s) { value["picture"] = s }
    }
    
    var website: String? {
        get { return value["website"]; }
        set(s) { value["website"] = s }
    }
    
    var lud06: String? {
        get { return value["lud06"]; }
        set(s) { value["lud06"] = s }
    }
    
    var lud16: String? {
        get { return value["lud16"]; }
        set(s) { value["lud16"] = s }
    }
    
    var lnurl: String? {
        guard let addr = lud06 ?? lud16 else {
            return nil;
        }
        
        if addr.contains("@") {
            return lnaddress_to_lnurl(addr);
        }
        
        return addr;
    }
    
    var nip05: String? {
        get { return value["nip05"]; }
        set(s) { value["nip05"] = s }
    }
    
    var lightning_uri: URL? {
        return make_ln_url(self.lnurl)
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.value = try container.decode([String: String].self)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
    
    static func displayName(profile: Profile?, pubkey: String) -> String {
        return profile?.name ?? abbrev_pubkey(pubkey)
    }
}

/*
struct Profile: Decodable {
    let name: String?
    let display_name: String?
    let about: String?
    let picture: String?
    let website: String?
    let nip05: String?
    let lud06: String?
    let lud16: String?
    
    var lightning_uri: URL? {
        return make_ln_url(self.lud06) ?? make_ln_url(self.lud16)
    }
    
    static func displayName(profile: Profile?, pubkey: String) -> String {
        return profile?.name ?? abbrev_pubkey(pubkey)
    }
}
 */

func make_ln_url(_ str: String?) -> URL? {
    return str.flatMap { URL(string: "lightning:" + $0) }
}

struct NostrSubscription {
    let sub_id: String
    let filter: NostrFilter
}

func lnaddress_to_lnurl(_ lnaddr: String) -> String? {
    let parts = lnaddr.split(separator: "@")
    guard parts.count == 2 else {
        return nil
    }
    
    let url = "https://\(parts[1])/.well-known/lnurlp/\(parts[0])";
    guard let dat = url.data(using: .utf8) else {
        return nil
    }
    
    return bech32_encode(hrp: "lnurl", Array(dat))
}
