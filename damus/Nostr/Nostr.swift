//
//  Nostr.swift
//  damus
//
//  Created by William Casarin on 2022-04-07.
//

import Foundation

class Profile: Codable {
    var value: [String: AnyCodable]
    
    init (name: String?, display_name: String?, about: String?, picture: String?, banner: String?, website: String?, lud06: String?, lud16: String?, nip05: String?, damus_donation: Int?) {
        self.value = [:]
        self.name = name
        self.display_name = display_name
        self.about = about
        self.picture = picture
        self.banner = banner
        self.website = website
        self.lud06 = lud06
        self.lud16 = lud16
        self.nip05 = nip05
        self.damus_donation = damus_donation
    }
    
    convenience init(persisted_profile: PersistedProfile) {
        self.init(name: persisted_profile.name,
                  display_name: persisted_profile.display_name,
                  about: persisted_profile.about,
                  picture: persisted_profile.picture,
                  banner: persisted_profile.banner,
                  website: persisted_profile.website,
                  lud06: persisted_profile.lud06,
                  lud16: persisted_profile.lud16,
                  nip05: persisted_profile.nip05,
                  damus_donation: Int(persisted_profile.damus_donation))
    }
    
    private func str(_ str: String) -> String? {
        return get_val(str)
    }
    
    private func int(_ key: String) -> Int? {
        return get_val(key)
    }
    
    private func get_val<T>(_ v: String) -> T? {
        guard let val = self.value[v] else{
            return nil
        }
        
        guard let s = val.value as? T else {
            return nil
        }
        
        return s
    }
    
    private func set_val<T>(_ key: String, _ val: T?) {
        if val == nil {
            self.value.removeValue(forKey: key)
            return
        }
        
        self.value[key] = AnyCodable.init(val)
    }
    
    private func set_str(_ key: String, _ val: String?) {
        set_val(key, val)
    }
    
    private func set_int(_ key: String, _ val: Int?) {
        set_val(key, val)
    }
    
    var reactions: Bool? {
        get { return get_val("reactions"); }
        set(s) { set_val("reactions", s) }
    }
    
    var deleted: Bool? {
        get { return get_val("deleted"); }
        set(s) { set_val("deleted", s) }
    }
    
    var display_name: String? {
        get { return str("display_name"); }
        set(s) { set_str("display_name", s) }
    }
    
    var name: String? {
        get { return str("name"); }
        set(s) { set_str("name", s) }
    }
    
    var about: String? {
        get { return str("about"); }
        set(s) { set_str("about", s) }
    }
    
    var damus_donation: Int? {
        get { return int("damus_donation"); }
        set(s) { set_int("damus_donation", s) }
    }
    
    var picture: String? {
        get { return str("picture"); }
        set(s) { set_str("picture", s) }
    }
    
    var banner: String? {
        get { return str("banner"); }
        set(s) { set_str("banner", s) }
    }
    
    var website: String? {
        get { return str("website"); }
        set(s) { set_str("website", s) }
    }
    
    var lud06: String? {
        get { return str("lud06"); }
        set(s) { set_str("lud06", s) }
    }
    
    var lud16: String? {
        get { return str("lud16"); }
        set(s) { set_str("lud16", s) }
    }
    
    var website_url: URL? {
        if self.website?.trimmingCharacters(in: .whitespacesAndNewlines) == "" {
            return nil
        }
        return self.website.flatMap { url in
            let trim = url.trimmingCharacters(in: .whitespacesAndNewlines)
            if !(trim.hasPrefix("http://") || trim.hasPrefix("https://")) {
                return URL(string: "https://" + trim)
            }
            return URL(string: trim)
        }
    }
    
    func cache_lnurl() {
        guard self._lnurl == nil else {
            return
        }
        
        guard let addr = lud16 ?? lud06 else {
            return
        }
        
        self._lnurl = lnaddress_to_lnurl(addr)
    }
    
    private var _lnurl: String? = nil
    var lnurl: String? {
        if let _lnurl {
            return _lnurl
        }
        
        guard let addr = lud16 ?? lud06 else {
            return nil;
        }
        
        if addr.contains("@") {
            // this is a heavy op and is used a lot in views, cache it!
            let addr = lnaddress_to_lnurl(addr);
            self._lnurl = addr
            return addr
        }
        
        if !addr.lowercased().hasPrefix("lnurl") {
            return nil
        }
        
        return addr;
    }
    
    var nip05: String? {
        get { return str("nip05"); }
        set(s) { set_str("nip05", s) }
    }
    
    var lightning_uri: URL? {
        return make_ln_url(self.lnurl)
    }
    
    init() {
        self.value = [:]
    }
    
    required init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.value = try container.decode([String: AnyCodable].self)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
    
    static func displayName(profile: Profile?, pubkey: String) -> DisplayName {
        return parse_display_name(profile: profile, pubkey: pubkey)
    }
}

func make_test_profile() -> Profile {
    return Profile(name: "jb55", display_name: "Will", about: "Its a me", picture: "https://cdn.jb55.com/img/red-me.jpg", banner: "https://pbs.twimg.com/profile_banners/9918032/1531711830/600x200",  website: "jb55.com", lud06: "jb55@jb55.com", lud16: nil, nip05: "jb55@jb55.com", damus_donation: 1)
}

func make_ln_url(_ str: String?) -> URL? {
    return str.flatMap { URL(string: "lightning:" + $0) }
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
