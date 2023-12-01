//
//  Keys.swift
//  damus
//
//  Created by William Casarin on 2022-05-21.
//

import Foundation
import secp256k1

let PUBKEY_HRP = "npub"

// some random pubkey
let ANON_PUBKEY = Pubkey(Data([
    0x85, 0x41, 0x5d, 0x63, 0x5c, 0x2b, 0xaf, 0x55,
    0xf5, 0xb9, 0xa1, 0xa6, 0xce, 0xb7, 0x75, 0xcc,
    0x5c, 0x45, 0x4a, 0x3a, 0x61, 0xb5, 0x3f, 0xe8,
    0x50, 0x42, 0xdc, 0x42, 0xac, 0xe1, 0x7f, 0x12
]))

struct FullKeypair: Equatable {
    let pubkey: Pubkey
    let privkey: Privkey

    func to_keypair() -> Keypair {
        return Keypair(pubkey: pubkey, privkey: privkey)
    }
}

struct Keypair {
    let pubkey: Pubkey
    let privkey: Privkey?
    //let pubkey_bech32: String
    //let privkey_bech32: String?

    static var empty: Keypair {
        Keypair(pubkey: .empty, privkey: nil)
    }

    func to_full() -> FullKeypair? {
        guard let privkey = self.privkey else {
            return nil
        }
        
        return FullKeypair(pubkey: pubkey, privkey: privkey)
    }

    static func just_pubkey(_ pk: Pubkey) -> Keypair {
        return .init(pubkey: pk, privkey: nil)
    }

    init(pubkey: Pubkey, privkey: Privkey?) {
        self.pubkey = pubkey
        self.privkey = privkey
        //self.pubkey_bech32 = pubkey.npub
        //self.privkey_bech32 = privkey?.nsec
    }
}

enum Bech32Key {
    case pub(Pubkey)
    case sec(Privkey)
}

func decode_bech32_key(_ key: String) -> Bech32Key? {
    guard let decoded = try? bech32_decode(key),
          decoded.data.count == 32
    else {
        return nil
    }

    if decoded.hrp == "npub" {
        return .pub(Pubkey(decoded.data))
    } else if decoded.hrp == "nsec" {
        return .sec(Privkey(decoded.data))
    }
    
    return nil
}

func bech32_privkey(_ privkey: Privkey) -> String {
    return bech32_encode(hrp: "nsec", privkey.bytes)
}

func bech32_pubkey(_ pubkey: Pubkey) -> String {
    return bech32_encode(hrp: "npub", pubkey.bytes)
}

func bech32_pubkey_decode(_ pubkey: String) -> Pubkey? {
    guard let decoded = try? bech32_decode(pubkey),
          decoded.hrp == "npub",
          decoded.data.count == 32
    else {
        return nil
    }

    return Pubkey(decoded.data)
}

func bech32_nopre_pubkey(_ pubkey: Pubkey) -> String {
    return bech32_encode(hrp: "", pubkey.bytes)
}

func bech32_note_id(_ evid: NoteId) -> String {
    return bech32_encode(hrp: "note", evid.bytes)
}

func generate_new_keypair() -> FullKeypair {
    let key = try! secp256k1.Signing.PrivateKey()
    let privkey = Privkey(key.rawRepresentation)
    let pubkey = Pubkey(Data(key.publicKey.xonly.bytes))
    return FullKeypair(pubkey: pubkey, privkey: privkey)
}

func privkey_to_pubkey_raw(sec: [UInt8]) -> Pubkey? {
    guard let key = try? secp256k1.Signing.PrivateKey(rawRepresentation: sec) else {
        return nil
    }
    return Pubkey(Data(key.publicKey.xonly.bytes))
}

func privkey_to_pubkey(privkey: Privkey) -> Pubkey? {
    return privkey_to_pubkey_raw(sec: privkey.bytes)
}

func save_pubkey(pubkey: Pubkey) {
    DamusUserDefaults.shared.set(pubkey.hex(), forKey: "pubkey")
}

enum Keys {
    @KeychainStorage(account: "privkey")
    static var privkey: String?
}

func save_privkey(privkey: Privkey) throws {
    Keys.privkey = privkey.hex()
}

func clear_saved_privkey() throws {
    Keys.privkey = nil
}

func clear_saved_pubkey() {
    DamusUserDefaults.shared.removeObject(forKey: "pubkey")
}

func save_keypair(pubkey: Pubkey, privkey: Privkey) throws {
    save_pubkey(pubkey: pubkey)
    try save_privkey(privkey: privkey)
}

func clear_keypair() throws {
    try clear_saved_privkey()
    clear_saved_pubkey()
}

func get_saved_keypair() -> Keypair? {
    do {
        try removePrivateKeyFromUserDefaults()

        guard let pubkey = get_saved_pubkey(),
              let pk = hex_decode(pubkey)
        else {
            return nil
        }

        let privkey = get_saved_privkey().flatMap { sec in
            hex_decode(sec).map { Privkey(Data($0)) }
        }

        return Keypair(pubkey: Pubkey(Data(pk)), privkey: privkey)
    } catch {
        return nil
    }
}

func get_saved_pubkey() -> String? {
    return DamusUserDefaults.shared.string(forKey: "pubkey")
}

func get_saved_privkey() -> String? {
    let mkey = Keys.privkey
    return mkey.map { $0.trimmingCharacters(in: .whitespaces) }
}

/**
 Detects whether a string might contain an nsec1 prefixed private key.
 It does not determine if it's the current user's private key and does not verify if it is properly encoded or has the right length.
 */
func contentContainsPrivateKey(_ content: String) -> Bool {
    if #available(iOS 16.0, *) {
        return content.contains(/nsec1[02-9ac-z]+/)
    } else {
        let regex = try! NSRegularExpression(pattern: "nsec1[02-9ac-z]+")
        return (regex.firstMatch(in: content, range: NSRange(location: 0, length: content.count)) != nil)
    }

}

fileprivate func removePrivateKeyFromUserDefaults() throws {
    guard let privkey_str = DamusUserDefaults.shared.string(forKey: "privkey"),
          let privkey = hex_decode_privkey(privkey_str)
    else { return }

    try save_privkey(privkey: privkey)
    DamusUserDefaults.shared.removeObject(forKey: "privkey")
}
