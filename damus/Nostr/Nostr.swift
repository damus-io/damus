//
//  Nostr.swift
//  damus
//
//  Created by William Casarin on 2022-04-07.
//

import Foundation

typealias Profile = NdbProfile
typealias ProfileKey = UInt64
//typealias ProfileRecord = NdbProfileRecord

class ProfileRecord {
    let data: NdbProfileRecord

    init(data: NdbProfileRecord, key: ProfileKey) {
        self.data = data
        self.profileKey = key
    }

    let profileKey: ProfileKey
    var profile: Profile? { return data.profile }
    var receivedAt: UInt64 { data.receivedAt }
    var noteKey: UInt64 { data.noteKey }

    private var _lnurl: String? = nil
    var lnurl: String? {
        if let _lnurl {
            return _lnurl
        }
        
        guard let profile = data.profile,
              let addr = profile.lud16 ?? profile.lud06 else {
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
    
}

extension NdbProfile {
    var display_name: String? {
        return displayName
    }

    static func displayName(profile: Profile?, pubkey: Pubkey) -> DisplayName {
        return parse_display_name(profile: profile, pubkey: pubkey)
    }

    var damus_donation: Int? {
        return Int(damusDonation)
    }

    var damus_donation_v2: Int {
        return Int(damusDonationV2)
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

    init(name: String? = nil, display_name: String? = nil, about: String? = nil, picture: String? = nil, banner: String? = nil, website: String? = nil, lud06: String? = nil, lud16: String? = nil, nip05: String? = nil, damus_donation: Int? = nil, reactions: Bool = true) {

        var fbb = FlatBufferBuilder()

        let name_off = fbb.create(string: name)
        let display_name_off = fbb.create(string: display_name)
        let about_off = fbb.create(string: about)
        let picture_off = fbb.create(string: picture)
        let banner_off = fbb.create(string: banner)
        let website_off = fbb.create(string: website)
        let lud06_off = fbb.create(string: lud06)
        let lud16_off = fbb.create(string: lud16)
        let nip05_off = fbb.create(string: nip05)

        let profile_data = NdbProfile.createNdbProfile(&fbb,
                                    nameOffset: name_off,
                                    websiteOffset: website_off,
                                    aboutOffset: about_off,
                                    lud16Offset: lud16_off,
                                    bannerOffset: banner_off,
                                    displayNameOffset: display_name_off,
                                    reactions: reactions,
                                    pictureOffset: picture_off,
                                    nip05Offset: nip05_off,
                                    damusDonation: 0,
                                    damusDonationV2: damus_donation.map({ Int32($0) }) ?? 0,
                                    lud06Offset: lud06_off)

        fbb.finish(offset: profile_data)

        var buf = ByteBuffer(bytes: fbb.sizedByteArray)
        let profile: Profile = try! getCheckedRoot(byteBuffer: &buf)
        self = profile
    }
}

/*
class Profile: Codable {
    var value: [String: AnyCodable]
    
    init(name: String? = nil, display_name: String? = nil, about: String? = nil, picture: String? = nil, banner: String? = nil, website: String? = nil, lud06: String? = nil, lud16: String? = nil, nip05: String? = nil, damus_donation: Int? = nil) {
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
        get { return int("damus_donation_v2"); }
        set(s) { set_int("damus_donation_v2", s) }
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
    
    static func displayName(profile: Profile?, pubkey: Pubkey) -> DisplayName {
        return parse_display_name(profile: profile, pubkey: pubkey)
    }
}
*/

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

